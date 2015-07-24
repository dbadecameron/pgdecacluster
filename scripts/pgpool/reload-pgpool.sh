#!/bin/bash
# -*- coding: utf-8 -*-
# 
# reload-pgpool.sh
# This file is part of pgdecacluster.
# 
# Copyright (C) 2013 - Víctor Daniel Martínez Olier
# Copyright (C) 2013 - Summan S.A.S.
# 
# pgdecacluster is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# pgdecacluster is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with pgdecacluster.  If not, see <http://www.gnu.org/licenses/>.
# 

. ~/../globals.cfg
. ~/data/conf/misc.cfg
. /pgcluster/scripts/funcs

BASE_NAME=`basename $0`
EXPECTED_MIN_ARGS=0
EXPECTED_MAX_ARGS=0
E_BADARGS=65

if [[ $# -gt $EXPECTED_MAX_ARGS ]] ||
   [[ $# -lt $EXPECTED_MIN_ARGS ]] ||
   [[ $1 == "--help" ]] ; then
  echo "Usage: $BASE_NAME --help" 1>&2
  exit $E_BADARGS
fi

if [ "$(id -u)" == "0" ]; then
   echo "$BASE_NAME: This script should not run as root." 1>&2
   exit 1
fi

BOLD_RED_TEXT='\033[1;31m'
BOLD_GREEN_TEXT='\033[1;32m'
BOLD_PURPLE_TEXT='\033[1;35m'
RESET_TEXT='\033[0m'
function echoRed() {
  echo -e "$BOLD_RED_TEXT$1$RESET_TEXT"
}

function echoGreen() {
  echo -e "$BOLD_GREEN_TEXT$1$RESET_TEXT"
}

function echoPurple() {
  echo -e "$BOLD_PURPLE_TEXT$1$RESET_TEXT"
}

function errorExit() {
  echoRed "There was an error. For protection, process is canceled."
  exit 1
}

LOCK_FILE="~/data/conf/pgpool.conf_lock"
ULIMIT_N=`ulimit -n`
let "FLOCK_FD = ULIMIT_N - 1"
START_DATE=`date`
ERROR_EXIT="1"

(
  eval "exec $FLOCK_FD<> $LOCK_FILE"
  if flock -n $FLOCK_FD ; then
  # flock START
    date >> ~/data/log/pgpool-reload.log
    
    if [ -e ~/data/conf/pgpool.conf_writing ] ; then
      echoRed "File ~/data/conf/pgpool.conf_writing exists. For protection, process is canceled."
      exit 1
    fi
    
    trap 'errorExit' SIGINT SIGTERM ERR
    set -o errexit
    cp -a ~/data/conf/pgpool.conf ~/data/conf/pgpool.conf_reload_backup
    
    if [ -e ~/data/conf/pgpool.conf_done ] ; then
      echoGreen "File ~/data/conf/pgpool.conf_done exists. Rewriting pgpool.conf..."
      echoGreen "NOTE: To change pgpool.conf manually remember to stop/pause additional components. Ex: pgpool-II dynamic balancer."
      
      DONE_LINES=`cat ~/data/conf/pgpool.conf_done | wc -l`
      CURRENT_LINES=`cat ~/data/conf/pgpool.conf | wc -l`
      
      if [[ $DONE_LINES == $CURRENT_LINES ]] ; then
        cat ~/data/conf/pgpool.conf_done > ~/data/conf/pgpool.conf
        rm -f ~/data/conf/pgpool.conf_done
      else
        echoRed "Lines in ~/data/conf/pgpool.conf and ~/data/conf/pgpool.conf_done differ. For protection, process is canceled."
        exit 1
      fi
    fi
    
    reloadPgPool
    mv ~/data/conf/pgpool.conf_reload_backup ~/data/conf/pgpool.conf_backup
  # flock END
  else
    echoGreen "$BASE_NAME: Another proccess is locking reload operation: $LOCK_FILE. Reload operation canceled."
  fi
)

