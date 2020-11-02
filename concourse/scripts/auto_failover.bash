gphome=/usr/local/greenplum-db-devel

function prepare_gpdb() {
    mkdir -p $gphome
    tar zxf bin_gpdb/*.tar.gz -C $gphome
    source $gphome/greenplum_path.sh
}
function install_pg_auto_failover() {
pushd gpdb_src/contrib/btree_gist
make install -j4
popd
pushd gpdb_src/contrib/pg_stat_statements
make install -j4
popd

pushd pg_auto_failover_src
make install -j4
popd
}

function prepare_test() {
cat > /home/gpadmin/test.sh <<-EOF
pushd $PWD/pg_auto_failover_src

. $gphome/greenplum_path.sh
TEST=single PGVERSION=12 make test

popd
EOF
}
function run_test() {
    bash /home/gpadmin/test.sh
}

function _main() {
time prepare_gpdb
time install_pg_auto_failover
time prepare_test
time run_test

}
_main
