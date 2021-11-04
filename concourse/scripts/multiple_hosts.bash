#!/bin/bash -l

set -eox pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${CWDIR}/common.bash"
GPSRC="$CWDIR/../.."
function prepare() {
  bash "$GPSRC/gpAux/gpdemo/multiple_hosts.bash" create
  bash "$GPSRC/gpAux/gpdemo/multiple_hosts.bash" create-cluster
}
function gen_env(){
  cat > /opt/run_test.sh <<-EOF
trap look4diffs ERR
echo "INTERNAL ENV:"
env

function look4diffs() {
  diff_files=\`find .. -name regression.diffs\`
  for diff_file in \${diff_files}; do
    if [ -f "\${diff_file}" ]; then
cat <<-FEOF

======================================================================
DIFF FILE: \${diff_file}
----------------------------------------------------------------------

\$(cat "\${diff_file}")

FEOF
    fi
  done
  exit 1
}
source /usr/local/greenplum-db-devel/greenplum_path.sh
source $GPSRC/gpAux/gpdemo/multiple_hosts_env.sh
cd "$GPSRC/gpMgmt"
flags="--tags=hostname_address --tags=~democluster,~concourse_cluster" \
  make -f Makefile.behave behave
EOF

  chmod a+x /opt/run_test.sh
}
function run_test() {
  echo "ENV:"
  env
  su gpadmin -c "ssh gpadmin@ns1 env PATH=$PATH bash /opt/run_test.sh"
}

function setup_gpadmin_user() {
  local testos=`determine_os`
  echo "TESTOS = $testos"
  $GPSRC/concourse/scripts/setup_gpadmin_user.bash "$testos"
}
function _main() {
  if [ -z "${MAKE_TEST_COMMAND}" ]; then
    echo "FATAL: MAKE_TEST_COMMAND is not set"
    exit 1
  fi
  time install_and_configure_gpdb
  time setup_gpadmin_user
  time prepare
  time install_python_requirements_on_single_host $GPSRC/gpMgmt/requirements-dev.txt
  time gen_env
  time run_test
}

_main "$@"
