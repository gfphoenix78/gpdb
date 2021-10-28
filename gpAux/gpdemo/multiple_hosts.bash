#!/bin/bash
set -exo

CWD=$(cd "$( dirname "${BASH_SOURCE[0]}")" && pwd)
echo "CWD=$CWD"
IPPREFIX=${IPPREFIX-10.123.11}
INTERNALPREFIX=10.123.119
NICPREFIX=${NICPREFIX-cauto}
NSEGMENTS=${NSEGMENTS-3}
NHOSTS=$((2 * NSEGMENTS + 2))
NSNAME=${NSNAME-ns}
BRIP=$IPPREFIX.254
BRNAME=${NICPREFIX}-br0
function CHECK_PARAMETER() {
  if [ "$2" == "" ]; then
    echo "parameter $1 not set" >&2
    exit 1
  fi
}

CHECK_PARAMETER IPPREFIX "$IPPREFIX"
CHECK_PARAMETER NICPREFIX "$NICPREFIX"
CHECK_PARAMETER NSEGMENTS "$NSEGMENTS"
CHECK_PARAMETER NSNAME "$NSNAME"
sshd_config_filename=/tmp/sshd_config_ns
function prepare_sshd_config() {
cp -f /etc/ssh/sshd_config ${sshd_config_filename}
cat >> ${sshd_config_filename} <<EOF
UseDNS no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
EOF
}
function create() {
local brname=$BRNAME
ip link add $brname type bridge
ip address add $BRIP/24 dev $brname
ip link add eth-internal type bridge
ip address add $INTERNALPREFIX.254/24 dev eth-internal
ip link set dev $brname up
ip link set dev eth-internal up
echo "$BRIP `hostname`" >> /etc/hosts
prepare_sshd_config
for((i=1; i<=NHOSTS; i++))
do
  local ns=${NSNAME}${i}
  local myip=$IPPREFIX.$i
  local inip=$INTERNALPREFIX.$i
  ip netns add $ns
  ip link add veth$i type veth peer name ieth$i
  ip link set ieth$i netns $ns
  ip link set veth$i master $brname
  # internal NIC
  ip link add iveth$i type veth peer name in-ieth$i
  ip link set in-ieth$i netns $ns
  ip link set iveth$i master eth-internal

  # assign address
  ip -netns $ns address add $myip/24 dev ieth$i
  ip -netns $ns address add $inip/24 dev in-ieth$i
  ip -netns $ns link set dev ieth$i    up
  ip -netns $ns link set dev in-ieth$i up
  ip -netns $ns link set dev lo        up
  ip            link set dev  veth$i up
  ip            link set dev iveth$i up

  # add route rules
  ip -netns $ns route add default via $BRIP

  # hostname
  echo "$myip    $ns" >> /etc/hosts
  echo "$inip    internal-$i" >> /etc/hosts
  # start sshd server
  ip netns exec $ns unshare -u bash -c "hostname $ns ; /usr/sbin/sshd -f ${sshd_config_filename}"
  su gpadmin bash -c "ssh-keyscan $myip $inip $ns internal-$i >> ~/.ssh/known_hosts"
done

# comment out the following iptable rule to enable
# net ns connect to the outside network.
# Replace the outgoing NIC name.
#iptables -t nat -A POSTROUTING -s $IPPREFIX.0/24 -o eth0 -j MASQUERADE
}

function destroy() {
local brname=$BRNAME
local hosts=/tmp/copy-hosts.tmp
cp -f /etc/hosts $hosts
sed -i "/$BRIP `hostname`/d" $hosts

for((i=1; i <= NHOSTS; i++))
do
  local ns=${NSNAME}${i}
  local pids="$(ip netns pids $ns)"
  [ -n "$pids" ] && kill $pids
  sleep 1
  pids="$(ip netns pids $ns)"
  [ -n "$pids" ] && kill -9 $pids
  ip netns delete $ns
  sed -i "/$IPPREFIX.$i    $ns/d" $hosts 
  sed -i "/$INTERNALPREFIX.$i    internal-$i/d" $hosts 
done
cat $hosts > /etc/hosts
ip link delete dev $brname
ip link delete dev eth-internal
# comment out the following iptable rule to enable
# net ns connect to the outside network.
# Replace the outgoing NIC name.
#iptables -t nat -D POSTROUTING -s $IPPREFIX.0/24 -o eth0 -j MASQUERADE
[ -d "$CWD/multi-home" ] && rm -rf "$CWD/multi-home"
}

# create cluster with segments separated by net namespace

function create_cluster() {
# create input configuration file
local PORT_BASE=7000
local datadir=$CWD/multi-home/qddir/demoDataDir-1
local QD_PRIMARY_ARRAY=ns1~internal-1~${PORT_BASE}~$datadir~1~-1
local PRIMARY_ARRAY=''
local dbid=2
local MDIR="$datadir"

# add host to known_hosts
for((i=1; i<NHOSTS; i++))
do
  local ns=${NSNAME}${i}
  local myip=$IPPREFIX.$i
  local inip=$INTERNALPREFIX.$i
#  ssh-keyscan 
done
mkdir -p "$(dirname $datadir)"

for((i=0; i<NSEGMENTS; i++))
do
  local ns=${NSNAME}${dbid}
  local datadir=$CWD/multi-home/dbfast$((i+1))/demoDataDir$i
  #mkdir -p "$datadir"
  mkdir -p "$(dirname $datadir)"
  PRIMARY_ARRAY="$PRIMARY_ARRAY $ns~internal-$dbid~$((PORT_BASE+dbid))~$datadir~$dbid~$i"
  dbid=$((dbid+1))
done
for((i=0; i<NSEGMENTS; i++))
do
  local ns=${NSNAME}${dbid}
  local datadir=$CWD/multi-home/dbfast_mirror$((i+1))/demoDataDir$i
  #mkdir -p "$datadir"
  mkdir -p "$(dirname $datadir)"
  MIRROR_ARRAY="$MIRROR_ARRAY $ns~internal-$dbid~$((PORT_BASE+dbid))~$datadir~$dbid~$i"
  dbid=$((dbid+1))
done
datadir=$CWD/multi-home/standby
local STANDBY_INIT_OPTS="-s internal-$dbid -P $((PORT_BASE+1)) -S $datadir"
#mkdir -p $datadir
mkdir -p "$(dirname $datadir)"
cat > $CWD/input_configuration_file <<EOF
COORDINATOR_HOSTNAME=ns1
TRUSTED_SHELL=/usr/bin/ssh
ENCODING=UNICODE
DEFAULT_QD_MAX_CONNECT=150
QE_CONNECT_FACTOR=5

QD_PRIMARY_ARRAY=$QD_PRIMARY_ARRAY
declare -a PRIMARY_ARRAY=(
$(echo $PRIMARY_ARRAY | tr ' ' '\n')
)
declare -a MIRROR_ARRAY=(
$(echo $MIRROR_ARRAY | tr ' ' '\n')
)
# STANDBY_INIT_OPTS=$STANDBY_INIT_OPTS
EOF
cat > $CWD/starter.sh <<EOF
#!/bin/bash
set -exo
. /usr/local/greenplum-db-devel/greenplum_path.sh
cd $CWD
echo "==> gpinitsystem -a -I input_configuration_file $STANDBY_INIT_OPTS"
gpinitsystem -a -I input_configuration_file $STANDBY_INIT_OPTS
. ./multiple_hosts_env.sh
psql postgres -c 'select * from gp_segment_configuration'
exit 0
EOF
chown gpadmin:gpadmin -R $CWD/multi-home $CWD/input_configuration_file $CWD/starter.sh
cat > $CWD/multiple_hosts_env.sh <<IEOF
export PGPORT=${PORT_BASE}
export MASTER_DATA_DIRECTORY=$MDIR
export COORDINATOR_DATA_DIRECTORY=$MDIR
IEOF
chown gpadmin:gpadmin $CWD/multiple_hosts_env.sh
su gpadmin -c "ssh gpadmin@ns1 bash $CWD/starter.sh"
exit 0
}

function destroy_cluster() {
echo "use destroy"
}

case "$1" in
  create)
    create
    ;;
  destroy)
    destroy
    ;;
  create-cluster)
    create_cluster
    ;;
  destroy-cluster)
    destroy_cluster
    ;;
  *)
    echo "unknown command:$1, valid commands: create|destroy" >&2
    exit 1
    ;;
esac
