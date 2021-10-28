#!/bin/bash -l

set -eox pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${CWDIR}/common.bash"
GPSRC="$CWDIR/../.."
function prepare() {
  bash "$GPSRC/gpAux/gpdemo/multiple_hosts.bash" create
  bash "$GPSRC/gpAux/gpdemo/multiple_hosts.bash" create-cluster
}
function setup_gpadmin_user() {
  local testos=`determine_os`
  echo "TESTOS = $testos"
  $GPSRC/concourse/scripts/setup_gpadmin_user.bash "$testos"
}
function _main() {
  time install_and_configure_gpdb
  time setup_gpadmin_user
  time prepare
}

_main "$@"
