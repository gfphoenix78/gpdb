#!/bin/bash

#export TARGET_OS=centos TARGET_OS_VERSION=7
#export CONFIGURE_FLAGS='--enable-cassert --enable-tap-tests --enable-debug-extensions --enable-orca'
#export BLD_TARGETS=clients
#export RC_BUILD_TYPE_GCS=.debug

mkdir -p gpdb_artifacts
pushd gpdb
CFLAGS="-O0 -g3 -ggdb -Og -Wno-maybe-uninitialized" ./configure --prefix=$USER/greenplum-db-devel \
   --with-gssapi --enable-mapreduce --enable-orafce \
   --enable-orca --with-libxml --with-pgport=7000 \
   --enable-cassert --enable-debug-extensions \
   --with-openssl
make
make install
popd

