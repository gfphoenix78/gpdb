#!/bin/bash

pghome=/home/gpadmin/postgres.bin
datadirs=/home/gpadmin/datadirs
mdatadir=$datadirs/pgm
sdatadir=$datadirs/pgs
ipprefix='10.123.119'
mport=5432
sport=5433
N=4
CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function prepareEnv() {
local vmdir=/home/gpadmin/VM
pkill -9 myinit 2>/dev/null
pkill -9 /usr/sbin/sshd
mkdir -p $vmdir
rm -rf $vmdir/*

for((i=1;i<=N;i++))
do
mkdir -p $vmdir/datadirs/node$i
mkdir -p $vmdir/config/node$i
mkdir -p $vmdir/local/node$i
mkdir -p $vmdir/tmp/node$i
done
chown gpadmin:gpadmin -R $vmdir
chmod 0750 $vmdir

for((i=1;i<=N;i++))
do
ip netns exec cauto$i unshare -m  bash <<EOF
#!/bin/bash
set -exo
mount -B --make-private -o 'rw' $vmdir/datadirs/node$i     /home/gpadmin/datadirs/
mount -B --make-private -o 'rw' $vmdir/config/node$i       /home/gpadmin/.config
mount -B --make-private -o 'rw' $vmdir/local/node$i        /home/gpadmin/.local
mount -B --make-private -o 'rw' $vmdir/tmp/node$i          /tmp
/usr/sbin/sshd
echo ">>>> i = $i"
#exit 0
EOF
done
/usr/sbin/sshd
pkill unshare
}
function export_pg() {
export PATH=$pghome/bin:$PATH
}

function initPGM0() {
export_pg
cleanDirs
initdb -kn -D $mdatadir
cat >> $mdatadir/postgresql.conf <<CEOF
hot_standby = on
listen_addresses = '*'
port = $mport
unix_socket_directories = ''
CEOF
cat >> $mdatadir/pg_hba.conf <<EOF
host replication all $ipprefix.0/24 trust
host all all $ipprefix.0/24 trust
EOF
pg_ctl -D $mdatadir -l $mdatadir/logfile start
}
function initPGS0() {
export_pg
cleanDirs
pg_basebackup -X stream -R -D $sdatadir -d postgres://$ipprefix.1/postgres
echo "port = $sport" >> $sdatadir/postgresql.conf
pg_ctl -D $sdatadir -l $sdatadir/logfile start
}
function initPG() {
destroy
local pgdata=/home/gpadmin/datadirs
ssh -tt gpadmin@$ipprefix.1 bash "$CWDIR/pg.bash initPGM0"
sleep 6
ssh -tt gpadmin@$ipprefix.2 bash "$CWDIR/pg.bash initPGS0"
}

monitorURI=''
function configPAF() {
configMonitor
sleep 6
configM
sleep 3
configS
}
function configMonitor() {
ssh -tt gpadmin@$ipprefix.3 bash "$CWDIR/pg.bash configMonitor0"
}
function configMonitor0() {
export_pg
cleanDirs
pg_autoctl create monitor --pgdata $datadirs/pgmonitor --hostname $ipprefix.3  --pgport 7999 --auth trust --no-ssl
cat >> $datadirs/pgmonitor/postgresql.conf <<CEOF
listen_addresses = '*'
#unix_socket_directories = ''
CEOF

cat >> $datadirs/pgmonitor/pg_hba.conf <<EOF
host all all 10.123.0.0/16 trust
host replication all 10.123.0.0/16 trust
EOF
setsid bash -c "pg_autoctl run --pgdata $datadirs/pgmonitor &"
exit 0
}
getMonitorURI() {
ssh gpadmin@$ipprefix.3 $pghome/bin/pg_autoctl show uri --pgdata $datadirs/pgmonitor --monitor
}
function configM() {
local monitorURI=`getMonitorURI`
echo "MURI = $monitorURI"
ssh -tt gpadmin@$ipprefix.1 bash "$CWDIR/pg.bash configM0 $monitorURI"
}
function configM0() {
local monitorURI="$1"
configNode pgm "$mdatadir" "$monitorURI" "$ipprefix.1" "$mport"
}

function configS() {
local monitorURI=`getMonitorURI`
ssh -tt gpadmin@$ipprefix.2 bash "$CWDIR/pg.bash configS0 $monitorURI"
}
function configS0() {
local monitorURI="$1"
configNode pgs "$sdatadir" "$monitorURI" "$ipprefix.2" "$sport"
}
function configNode() {
local name="$1"
local pgdata="$2"
local monitorURI="$3"
local pghost="$4"
local pgport="$5"
export_pg
pg_ctl stop -D $pgdata
echo "monitor uri:'$monitorURI'"
pg_autoctl create postgres --pgdata $pgdata --pgport $pgport --hostname $pghost --pghost $pghost --name $name --monitor "$monitorURI" --auth trust --no-ssl
setsid bash -c "pg_autoctl run --pgdata $pgdata &"
exit 0
}

function stop() {
pkill -SIGTERM pg_autoctl
pkill -SIGTERM postgres
sleep 1
pkill -9 pg_autoctl 2>/dev/null
pkill postgres 2>/dev/null

}
function startpgi() {
local pgdata="$1"
local index="$2"
ssh -tt gpadmin@$ipprefix.$index bash <<EOF
export PATH=$pghome/bin:$PATH
setsid bash -c "pg_autoctl run --pgdata $pgdata &"
exit 0
EOF
}

function _startraw() {
local datadir="$1"
local index="$2"
ssh -tt gpadmin@$ipprefix.$index bash <<EOF
export PATH=$pghome/bin:$PATH
setsid bash -c "pg_ctl -D $datadir start &"
exit 0
EOF
}
function startPG() {
_startraw $mdatadir 1
_startraw $sdatadir 2
}
function startMS() {
startpgi $datadirs/pgmonitor 3
sleep 8
startpgi $mdatadir 1
sleep 5
startpgi $sdatadir 2
}
function startSM() {
start0
startpgi $datadirs/pgmonitor 3
sleep 8
startpgi $sdatadir 2
sleep 5
startpgi $mdatadir 1
}

function cleanDirs() {
rm -rf /tmp/.s* 2>/dev/null
rm -rf /tmp/pg_autoctl 2>/dev/null
rm -rf /home/gpadmin/.config/pg_autoctl 2>/dev/null
rm -rf /home/gpadmin/.local/share/pg_autoctl 2>/dev/null
rm -rf $datadirs/* 2>/dev/null
}
function destroy() {
pkill -9 pg_autoctl
pkill -9 postgres
cleanDirs
sleep 2
}

$*
