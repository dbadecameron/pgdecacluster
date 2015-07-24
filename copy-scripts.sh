#!/bin/bash

pushd `dirname $0` > /dev/null
SCRIPT_PATH=`pwd`
popd > /dev/null

. "$SCRIPT_PATH/config.cfg"

cp -r $SCRIPT_PATH/scripts/* /pgcluster/scripts

