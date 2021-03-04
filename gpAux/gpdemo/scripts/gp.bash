#!/bin/bash

DATADIRS=/home/gpadmin/datadirs
ipprefix='10.123.119'

function destroy() {
pgdata=$DATADIRS
pkill -9 pg_autoctl
pkill -9 postgres
rm /tmp/.s* /tmp/pg_autoctl /home/gpadmin/.config/pg_autoctl /home/gpadmin/.local/share/pg_autoctl -rf 2>/dev/null
rm -rf $pgdata/* 2>/dev/null
}

function initGPDB() {
destroy
pgdata=$DATADIRS

# start ssh server in the NSes
# init segments
ip netns exec cauto4 su -l gpadmin -c bash <<EOF
set -exo
. /usr/local/greenplum-db-devel/greenplum_path.sh
initdb -kn -D $pgdata/node1 >/dev/null
cat >> $pgdata/node1/postgresql.conf <<CEOF
#hot_standby = on
listen_addresses = '*'
unix_socket_directories = ''
CEOF

cat >> $pgdata/node1/pg_hba.conf <<CEOF
host all all $ipprefix.0/24 trust
host replication all $ipprefix.0/24 trust
CEOF

cp -r $pgdata/node1 $pgdata/node3
cp -r $pgdata/node1 $pgdata/node5
idx=0
dbid=3
dbids=(2 3 4 5 6 7)
content=(-1 0 0 1 1 2 2)
ports=(7002 7003 7004 7005 7006 7007)

for((i=1;i<6;i+=2))
do

datadir="$pgdata/node\$i"
datadir2="$pgdata/node\$((i+1))"
port=\${ports[idx]}
port2=\${ports[idx+3]}
#
    echo "gp_contentid = \$idx" >> "\$datadir/postgresql.conf"
    echo "gp_dbid=\${dbids[idx]}" > "\$datadir/internal.auto.conf"
    pg_ctl -D \$datadir -o "-p \$port -c gp_role=execute" -l \$datadir/logfile start
    pg_basebackup -X stream -R --target-gp-dbid \${dbids[idx+3]} -D "\$datadir2" -d "postgres://$ipprefix.4:\$port/postgres"
#
#    # update dbid, port
    echo "port = \$port" >> "\$datadir/postgresql.conf"
    echo "port = \${port2}" >> "\$datadir2/postgresql.conf"
    echo "gp_dbid=\${dbids[idx+3]}" > "\$datadir2/internal.auto.conf"
#
    pg_ctl -D \$datadir2 -o "-p \$port2 -c gp_role=execute" -l \$datadir2/logfile start
    echo "i = \$idx"
    idx=\$((idx+1))
done

EOF

segip="$ipprefix.4"
sdbid=8
ip netns exec cauto1 su -l gpadmin -c bash <<EOF
. /usr/local/greenplum-db-devel/greenplum_path.sh
initdb -kn -D $pgdata/nodeM >/dev/null
cat >> $pgdata/nodeM/postgresql.conf <<CEOF
hot_standby = on
listen_addresses = '*'
unix_socket_directories = ''
gp_contentid = -1
CEOF
echo "host all all $ipprefix.0/24 trust"  >> $pgdata/nodeM/pg_hba.conf
echo "host replication all $ipprefix.0/24 trust"  >> $pgdata/nodeM/pg_hba.conf
echo "gp_dbid = 1" > $pgdata/nodeM/internal.auto.conf

postgres --single -D $pgdata/nodeM -O postgres <<PQEOF
insert into gp_segment_configuration select i+2,i,'p','p','s','u',i+7002,'$segip','$segip','$pgdata/node'||(2*i+1) from generate_series(0,2)i
insert into gp_segment_configuration select i+5,i,'m','m','s','u',i+7005,'$segip','$segip','$pgdata/node'||(2*i+2) from generate_series(0,2)i
insert into gp_segment_configuration values(1,-1, 'p', 'p', 's', 'u',7000,'$ipprefix.1', '$ipprefix.1', '$pgdata/nodeM')
insert into gp_segment_configuration values($sdbid,-1,'m','m','s','u',7001,'$ipprefix.2', '$ipprefix.2', '$pgdata/nodeS')
PQEOF

pg_ctl -D $pgdata/nodeM -l $pgdata/nodeM/logfile -o "-p 7000 -c gp_role=dispatch" start
EOF

ip netns exec cauto2 su -l gpadmin -c bash <<EOF
. /usr/local/greenplum-db-devel/greenplum_path.sh
pg_basebackup -X stream -R --target-gp-dbid $sdbid -D $pgdata/nodeS -d postgres://$ipprefix.1:7000/postgres
echo "gp_dbid = $sdbid" > $pgdata/nodeM/internal.auto.conf
echo "port = 7000" >> $pgdata/nodeM/postgresql.conf
echo "port = 7001" >> $pgdata/nodeS/postgresql.conf
pg_ctl -D $pgdata/nodeS -l $pgdata/nodeS/logfile -o "-p 7001 -c gp_role=dispatch" start
EOF

}

function configMonitor() {
ip netns exec cauto3 su -l gpadmin -c bash <<EOF
set -exo
. /usr/local/greenplum-db-devel/greenplum_path.sh
pg_autoctl create monitor --pgdata $DATADIRS/pgmonitor --pgport 7999 --auth trust --ssl-self-signed
cat >> $DATADIRS/pgmonitor/postgresql.conf <<CEOF
listen_addresses = '*'
unix_socket_directories = ''
CEOF
setsid pg_autoctl run --pgdata $DATADIRS/pgmonitor &
EOF
}
function configM() {
pgdata=$DATADIRS/nodeM
#ip netns exec cauto1 su -l gpadmin -c bash <<EOF
#set -exo
. /usr/local/greenplum-db-devel/greenplum_path.sh
pg_ctl stop -D $pgdata 2>/dev/null
monitorURI=`pg_autoctl show uri --pgdata "$DATADIRS/pgmonitor" --monitor`
echo monitor uri:$monitorURI
pg_autoctl create postgres --pgdata $pgdata --pgport 7000 --pghost $ipprefix.1 --name pgm --monitor "$monitorURI" --auth trust --ssl-self-signed --gp_dbid 1 --gp_role dispatch
setsid pg_autoctl run --pgdata $pgdata &

#EOF
}

function configS() {
pgdata=$DATADIRS/nodeS
#ip netns exec cauto2 su gpadmin -c bash <<EOF
. /usr/local/greenplum-db-devel/greenplum_path.sh
pg_ctl stop -D $pgdata
monitorURI=`pg_autoctl show uri --pgdata "$DATADIRS/pgmonitor" --monitor`
echo "monitor uri:'$monitorURI'"
pg_autoctl create postgres --pgdata $pgdata --pgport 7001 --pghost $ipprefix.2 --name pgs --monitor "$monitorURI" --auth trust --ssl-self-signed --gp_dbid 8 --gp_role dispatch
setsid pg_autoctl run --pgdata $pgdata &

#EOF
}

function stop() {
pkill pg_autoctl
pkill postgres
sleep 1
pkill -9 pg_autoctl 2>/dev/null
pkill postgres 2>/dev/null

}
function startpgi() {
local pgdata="$DATADIRS/$2"
ip netns exec "$1" su -l gpadmin -c bash <<EOF
. /usr/local/greenplum-db-devel/greenplum_path.sh
setsid pg_autoctl run --pgdata $pgdata &
EOF
}

function start0() {
for((i=1;i<=6;i++))
do
ip netns exec cauto4 su -l gpadmin -c bash <<EOF
. /usr/local/greenplum-db-devel/greenplum_path.sh
pg_ctl -D $DATADIRS/node$i -o '-c gp_role=execute' start
EOF
done
}
function _startraw() {
local datadir="$DATADIRS/$1"
local role="$2"
local netns="$3"
if [[ -z "$netns" ]]; then
su -l gpadmin -c bash <<EOF
. /usr/local/greenplum-db-devel/greenplum_path.sh
pg_ctl -D $datadir -o '-c gp_role=$role' start
EOF
else
ip netns exec "$netns" su -l gpadmin -c bash <<EOF
. /usr/local/greenplum-db-devel/greenplum_path.sh
pg_ctl -D $datadir -o '-c gp_role=$role' start
EOF
fi
}
function startGP() {
start0
_startraw nodeM dispatch cauto1
_startraw nodeS dispatch cauto2
}
function startMS() {
start0
startpgi cauto3 pgmonitor
sleep 8
startpgi cauto1 nodeM
sleep 5
startpgi cauto2 nodeS
}
function startSM() {
start0
startpgi cauto3 pgmonitor
sleep 8
startpgi cauto2 nodeS
sleep 5
startpgi cauto1 nodeM
}

$1
