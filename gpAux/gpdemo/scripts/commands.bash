#
MONITOR_HOST=10.123.119.10
MONITOR_PORT=7999
MONITOR_DATADIR=/home/gpadmin/datadirs/M/gpmonitor

MASTER_DATA_DIRECTORY=${MASTER_DATA_DIRECTORY:-/home/gpadmin/datadirs/entry/entry-1}
C_PORT=${C_PORT:-7000}

ipprefix='10.123.119'
N=10

# postgres://10.123.119.8:7001,10.123.119.1:7000/postgres?target_session_attrs=read-write
# gpcaf -m deconfig --single 1 -M 10.123.119.10:7999 -D /home/gpadmin/datadirs/M/gpmonitor -c 10.123.119.8:7001

# MASTER_DATA_DIRECTORY=/home/gpadmin/datadirs/entry/standby-1 PGPORT=7001 gpinitstandby -s 10.123.119.9 -P 7010 -S /home/gpadmin/datadirs/entry/m2 -m 10.123.119.10,7999,/home/gpadmin/datadirs/M/gpmonitor


function init0() {
gpinitsystem -I scripts/ccFile
MASTER_DATA_DIRECTORY=/home/gpadmin/datadirs/entry/entry-1 PGPORT=7000 gpinitstandby -s $ipprefix.8 -P 7001 -S /home/gpadmin/datadirs/entry/standby-1
}
function config0() {
gpcaf -m config -M $MONITOR_HOST:$MONITOR_PORT -D $MONITOR_DATADIR -c $C_HOST:$C_PORT
}
function deconfig() {
gpcaf -m deconfig -M $MONITOR_HOST:$MONITOR_PORT -D $MONITOR_DATADIR -c $C_HOST:$C_PORT
}

function gpstart() {
MONITOR_HOST=$MONITOR_HOST MONITOR_PORT=$MONITOR_PORT MONITOR_DATADIR=$MONITOR_DATADIR MASTER_DATA_DIRECTORY=$MASTER_DATA_DIRECTORY $GPHOME/bin/gpstart -a
}
function gpstop() {
MONITOR_HOST=$MONITOR_HOST MONITOR_PORT=$MONITOR_PORT MONITOR_DATADIR=$MONITOR_DATADIR MASTER_DATA_DIRECTORY=$MASTER_DATA_DIRECTORY $GPHOME/bin/gpstop -a
}


function show() {
MONITOR_HOST=$MONITOR_HOST MONITOR_PORT=$MONITOR_PORT MONITOR_DATADIR=$MONITOR_DATADIR MASTER_DATA_DIRECTORY=$MASTER_DATA_DIRECTORY env
}

function clean() {
# run in main env
pkill -9 pg_autoctl
pkill -9 postgres
local vmdir=/home/gpadmin/VM

pushd $vmdir/datadirs

mkdir -p node{1,8,9}/entry
mkdir -p node{2,3,4}/seg
mkdir -p node{5,6,7}/mirror
mkdir -p node10/M

rm -rf node{1,8,9}/entry/*
rm -rf node{2,3,4}/seg/*
rm -rf node{5,6,7}/mirror/*
rm -rf node10/M/*
popd

pushd $vmdir
find . -type f -exec rm -f {} \;
popd
}

function prepareEnv() {
# assume network namespace is setup properly
# run as root
local vmdir=/home/gpadmin/VM
mkdir -p $vmdir
rm -rf $vmdir/*
for((i=1;i<=N;i++))
do
mkdir -p $vmdir/datadirs/node$i
mkdir -p $vmdir/config/node$i
mkdir -p $vmdir/local/node$i
mkdir -p $vmdir/tmp/node$i
done

pkill -9 myinit 2>/dev/null
pkill -9 /usr/sbin/sshd

pushd $vmdir/datadirs
mkdir -p node{1,8,9}/entry
mkdir -p node{2,3,4}/seg
mkdir -p node{5,6,7}/mirror
mkdir -p node10/M
popd
chown gpadmin:gpadmin -R $vmdir

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
#unshare -pf --mount-proc myinit &
exit 0
EOF
done
/usr/sbin/sshd
pkill unshare
}

$*
