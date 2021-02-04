#!/bin/bash

ipprefix=10.123.119
masterIP="$ipprefix".1
standbyIP="$ipprefix".2
monitorIP="$ipprefix".3
segsIP="$ipprefix".4
DATADIRS=/home/gpadmin/datadirs

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

initGPDB() {
destroy
ssh gpadmin@$segsIP bash "$CWDIR/gpfunc.bash initSegs"
ssh gpadmin@$masterIP bash "$CWDIR/gpfunc.bash initM"
ssh gpadmin@$standbyIP bash "$CWDIR/gpfunc.bash initS"
}
destroy() {
bash $CWDIR/gpfunc.bash destroy
}

configPAF() {
configMonitor
sleep 6
configM
sleep 3
configS
}
configMonitor() {
ssh -tt gpadmin@$monitorIP bash "$CWDIR/gpfunc.bash configMonitor"
}
getMonitorURI() {
ssh gpadmin@$monitorIP /usr/local/greenplum-db-devel/bin/pg_autoctl show uri --pgdata $DATADIRS/pgmonitor --monitor
}
configM() {
local monitorURI=`getMonitorURI`
ssh -tt gpadmin@$masterIP bash "$CWDIR/gpfunc.bash configM $monitorURI"
}

configS() {
local monitorURI=`getMonitorURI`
ssh -tt gpadmin@$standbyIP bash "$CWDIR/gpfunc.bash configS $monitorURI"
}

startPAF() {
ssh -tt gpadmin@$segsIP bash "$CWDIR/gpfunc.bash startSegs"
ssh -tt gpadmin@$monitorIP bash "$CWDIR/gpfunc.bash autoctlRun $DATADIRS/pgmonitor"
# TODO: MUST start active master first, OR the standby is promoted 
sleep 6
ssh -tt gpadmin@$masterIP bash "$CWDIR/gpfunc.bash autoctlRun $DATADIRS/nodeM"
sleep 3
ssh -tt gpadmin@$standbyIP bash "$CWDIR/gpfunc.bash autoctlRun $DATADIRS/nodeS"
}
stopPAF() {
pkill -SIGTERM pg_autoctl
sleep 2
ssh -tt gpadmin@$segsIP bash "$CWDIR/gpfunc.bash stopSegs"
}

dropNode() {
local datadir="$1"
local index="$2"
ssh -tt gpadmin@$ipprefix.$index bash <<EOF
. /usr/local/greenplum-db-devel/greenplum_path.sh
pg_autoctl drop node --pgdata $datadir
EOF
}
addNode() {
local pgdata="$1"
local index="$2"
local port="$3"
local name="$4"
local dbid="$5"
local monitorURI=`getMonitorURI`
ssh -tt gpadmin@$ipprefix.$index bash "$CWDIR/gpfunc.bash configNode '$pgdata' $index $port $name '$monitorURI' $dbid"
}

$*
