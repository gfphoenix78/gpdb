#!/bin/bash
IPPREFIX=10.123.119
function doAddAction() {
iptables -C FORWARD -s $IPPREFIX.$1 -d $IPPREFIX.$2 -j $3 2>/dev/null
if [[ "$?" -ne 0 ]]; then
iptables -A FORWARD -s $IPPREFIX.$1 -d $IPPREFIX.$2 -j $3
fi
}
function doDelAction() {
iptables -D FORWARD -s $IPPREFIX.$1 -d $IPPREFIX.$2 -j $3 2>/dev/null
}

function udrop() {
doAddAction $1 $2 DROP
}
function bdrop() {
udrop $1 $2
udrop $2 $1
}
function ureject() {
doAddAction $1 $2 REJECT
}
function breject() {
ureject $1 $2
ureject $2 $1
}
function uhealth() {
doDelAction $1 $2 DROP
doDelAction $1 $2 REJECT
}
function bhealth() {
uhealth $1 $2
uhealth $2 $1
}
function show() {
iptables -nL
}
function icmd() {
echo "'$#' '$*' '$@'"
if [[ "$#" -ne 3 ]]; then
print_help
return 1
fi
local cmd="$1"
local from="$2"
local to="$3"
echo "cmd='$cmd', '$from' => '$to'"
if [[ -z "$from" || -z "$to" ]]; then
echo "from or to can't be empty" >&2
return 1
fi
$cmd $from $to
}

function print_help() {
echo "$name {show | help}"
echo "$name {udrop | bdrop | ureject | breject | uhealth | bhealth } {1 | 2 | 3} {1 | 2 | 3}"
echo "      1: master"
echo "      2: standby"
echo "      3: monitor"
return 0
}

case $1 in
    show)
        show
        ;;
    udrop|bdrop|ureject|breject|uhealth|bhealth)
        icmd $*
        ;;
    *)
        print_help
        ;;
esac
