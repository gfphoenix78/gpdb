#!/bin/bash

# init ns
# 10.123.X.1 ip address in the default network namespace
# 10.123.X.2 ip address in the isolated network namespace
# 10.123.X.Y, X=1...9, Y=1,2
# https://man7.org/linux/man-pages/man8/ip-link.8.html
# https://man7.org/linux/man-pages/man8/ip-link.8.html

N=10
DEFAULT_PREFIX='cauto'
DEFAULT_OIF=`ip r | grep default | sed -n 's/.*dev//p'`

function run_this() {
echo "$*"
$*
}

function initns() {
local prefix="$1"
local oif="$2"
[ -z "$prefix" ] && prefix="$DEFAULT_PREFIX"
[ -z "$oif" ] && oif="$DEFAULT_OIF"
local OETH=$oif

for((i=1;i<=N;i++))
do

local ns=${prefix}$i
ip netns add $ns
ip link add veth$i type veth peer name ieth$i
ip link set ieth$i netns $ns

# assign address
ip            address add 10.123.$i.1/24 dev veth$i
ip -netns $ns address add 10.123.$i.2/24 dev ieth$i
ip            link set dev veth$i up
ip -netns $ns link set dev ieth$i up
ip -netns $ns link set dev lo up

# add route rule
ip netns exec $ns ip route add default via 10.123.$i.1
done

# add iptables rule of SNAT to allow the process
# in the isolated network namespace to connect to
# the outside network
run_this iptables -t nat -A POSTROUTING -s 10.123.0.0/16 -o $OETH -j MASQUERADE
}

function cleanns() {
local prefix="$1"
local oif="$2"
[ -z "$prefix" ] && prefix="$DEFAULT_PREFIX"
[ -z "$oif" ] && oif=$DEFAULT_OIF
local OETH=$oif

for((i=1;i<=N;i++))
do
ip netns delete ${prefix}$i
done

run_this iptables -t nat -D POSTROUTING -s 10.123.0.0/16 -o $OETH -j MASQUERADE
}

function initns2() {
local prefix="$1"
local oif="$2"
[ -z "$prefix" ] && prefix="$DEFAULT_PREFIX"
[ -z "$oif" ] && oif=$DEFAULT_OIF
local OETH=$oif
local ipprefix='10.123.119'
local gwip=$ipprefix.254
local brname=$prefix-br0
ip link add $brname type bridge
ip address add $gwip/24 dev $brname

for((i=1;i<=N;i++))
do

local ns=${prefix}$i
ip netns add $ns
ip link add veth$i type veth peer name ieth$i
ip link set ieth$i netns $ns
ip link set veth$i master $prefix-br0

# assign address
ip -netns $ns address add $ipprefix.$i/24 dev ieth$i
ip            link set dev veth$i up
ip -netns $ns link set dev ieth$i up
ip -netns $ns link set dev lo up

# add route rule
ip -netns $ns route add default via $gwip
done
ip link set dev $brname up

# add iptables rule of SNAT to allow the process
# in the isolated network namespace to connect to
# the outside network
run_this iptables -t nat -A POSTROUTING -s 10.123.0.0/16 -o $OETH -j MASQUERADE
}
function cleanns2() {
local prefix="$1"
local oif="$2"
[ -z "$prefix" ] && prefix="$DEFAULT_PREFIX"
[ -z "$oif" ] && oif=$DEFAULT_OIF
local OETH=$oif
local brname=$prefix-br0

for((i=1;i<=N;i++))
do
local ns=${prefix}$i
ip l del dev veth$i
ip netns delete $ns
done
ip link delete dev $brname type bridge

run_this iptables -t nat -D POSTROUTING -s 10.123.0.0/16 -o $OETH -j MASQUERADE
}

$*

