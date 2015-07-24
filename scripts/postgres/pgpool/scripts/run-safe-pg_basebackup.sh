#!/bin/bash -x
# -*- coding: utf-8 -*-
# 
# run-safe-pg_basebackup.sh
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
. /pgcluster/scripts/funcs

BASE_NAME=`basename $0`
EXPECTED_MIN_ARGS=4
EXPECTED_MAX_ARGS=4
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

LOCK_FILE="~/.run-safe-pg_basebackup-DELETEME.lock"
ULIMIT_N=`ulimit -n`
let "FLOCK_FD = ULIMIT_N - 1"
START_DATE=`date`
ERROR_EXIT="1"

(
  eval "exec $FLOCK_FD<> $LOCK_FILE"
  if flock -n $FLOCK_FD ; then
  # flock START
  
  PG_BASEBACKUP="/opt/PostgresPlus/9.xAS/bin/pg_basebackup"
  PG_CTL="/opt/PostgresPlus/9.xAS/bin/pg_ctl"
  REMOTE_USER=$1
  REMOTE_PORT=$2
  REMOTE_IP=$3
  LOCAL_PGDATA=$4

  echo "Validating if EDB is running..."
  if $PG_CTL -D $LOCAL_PGDATA status | 
     grep -q "server is running" ; then
    echo "$BASE_NAME: EDB is running."

    rm -f ~/.run-safe-pg_basebackup-DELETEME.lock
    exit $ERROR_EXIT
  else
    echo "Validating if remote server is running another backup..."
    export PGPASSFILE=`mktemp -t tmp.\`whoami\`.XXXXXXXXXX`
    chmod 'u=rw,g=,o=' "$PGPASSFILE"
    echo \
     "$REMOTE_IP:$REMOTE_PORT:template1:$PGPOOL_USER:$PGPOOL_PASSWORD" > \
     "$PGPASSFILE"
    IS_IN_BACKUP=`psql -x -U $PGPOOL_USER \
                          -h $REMOTE_IP \
                          -p $REMOTE_PORT \
                          -c "SELECT pg_is_in_backup()" \
                          -w template1 |
                  grep pg_is_in_backup | awk '{print $3}'`
    rm -f "$PGPASSFILE"
    unset PGPASSFILE

    if [ "$IS_IN_BACKUP" != "f" ] ; then
      echo "$BASE_NAME: Remote server pg_is_in_backup() == '$IS_IN_BACKUP'."

      rm -f ~/.run-safe-pg_basebackup-DELETEME.lock
      exit $ERROR_EXIT
    else
      echo "Moving old data..."
      mkdir "$LOCAL_PGDATA/OLD_CLUSTER"
      mv "$LOCAL_PGDATA/../../data/pgdata/"* "$LOCAL_PGDATA/OLD_CLUSTER/" # safing code
      mkdir "$LOCAL_PGDATA/OLD_CLUSTER_LOGS"
      mv "$LOCAL_PGDATA/OLD_CLUSTER/pg_log/"* "$LOCAL_PGDATA/OLD_CLUSTER_LOGS"

      set -e
      echo "Deleting old cluster..."
      rm -rf "$LOCAL_PGDATA/../../data/pgdata/OLD_CLUSTER" # safing code

      mkdir $LOCAL_PGDATA/NEW_CLUSTER
      echo "Runing pg_basebackup..."
      time \
      $PG_BASEBACKUP --write-recovery-conf \
                     --xlog \
                     --checkpoint=fast \
                     --label="$BASE_NAME" \
                     --host="$REMOTE_IP" \
                     --port="$REMOTE_PORT" \
                     --username="$REMOTE_USER" \
                     --no-password \
                     --pgdata="$LOCAL_PGDATA/NEW_CLUSTER"

      echo "Preparing new cluster..."
      pushd "$LOCAL_PGDATA/../../xlog/pgxlog"
        LOCAL_PGXLOG=`pwd`
      popd
      mv "$LOCAL_PGDATA/NEW_CLUSTER/"* "$LOCAL_PGDATA/../../data/pgdata/"
      rmdir "$LOCAL_PGDATA/NEW_CLUSTER"
      set +e
      rm -f "$LOCAL_PGDATA/pg_log/"*
      mv "$LOCAL_PGDATA/OLD_CLUSTER_LOGS/"* "$LOCAL_PGDATA/pg_log/"
      rmdir "$LOCAL_PGDATA/OLD_CLUSTER_LOGS"
      rm -f "$LOCAL_PGXLOG/../../xlog/pgxlog/"*
      rm -f "$LOCAL_PGXLOG/archive_status/"*
      rmdir "$LOCAL_PGXLOG/archive_status"
      mv "$LOCAL_PGDATA/pg_xlog/"* "$LOCAL_PGXLOG/../../xlog/pgxlog/"
      rmdir "$LOCAL_PGDATA/pg_xlog"
      set -e
      ln -s "$LOCAL_PGXLOG" "$LOCAL_PGDATA/pg_xlog"
      ln -s /pgcluster/scripts/postgres/pgpool "$LOCAL_PGDATA"
      pushd "$LOCAL_PGDATA"
      ln -s pgpool/scripts/pgpool_remote_start
      popd
      rm -f "$LOCAL_PGDATA/postmaster.pid"
      rm -f "$LOCAL_PGDATA/postmaster.opts"
      rm -f "$LOCAL_PGDATA/recovery.done"
      rm -f "$LOCAL_PGDATA/make_me_master"
    fi
  fi

  rm -f ~/.run-safe-pg_basebackup-DELETEME.lock
  END_DATE=`date`
  exit 0

  # flock END
  else
    echo "$BASE_NAME: Another proccess is locking pg_basebackup operation: $LOCK_FILE. pg_basebackup operation canceled."
    exit $ERROR_EXIT
  fi
)

