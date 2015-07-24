#!/bin/bash
# -*- coding: utf-8 -*-
# 
# sync-pg-pw.sh
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

PG_USERNAME=`getPgPoolConf recovery_user`
PG_PASSWORD=`getPgPoolConf recovery_password`
PG_HOSTNAME=`getPgPoolConf listen_addresses`
PG_PORT=`getPgPoolConf port`
export PGPASSFILE=`mktemp -t tmp.\`whoami\`.XXXXXXXXXX`
chmod 'u=rw,g=,o=' "$PGPASSFILE"
TEMP_PASSWD_FILE=`mktemp -t tmp.\`whoami\`.XXXXXXXXXX`
chmod 'u=rw,g=,o=' "$TEMP_PASSWD_FILE"

echo "$PG_HOSTNAME:$PG_PORT:template1:$PG_USERNAME:$PG_PASSWORD" > "$PGPASSFILE"

trap exit SIGINT SIGTERM ERR
echo -e "COPY (SELECT rolname,rolpassword AS passwd FROM pg_authid WHERE rolpassword IS NOT Null) TO STDOUT WITH CSV;" | \
 psql -w -U "$PG_USERNAME" -h "$PG_HOSTNAME" -p "$PG_PORT" template1 | \
 awk -F"," '{print $1":"$2 }' | sort > "$TEMP_PASSWD_FILE"
trap '' SIGINT SIGTERM ERR

if [[ `cat "$TEMP_PASSWD_FILE" | wc -l` -lt $MIN_PASSWD_LINES ]] ; then
  echo "Few lines to continue. Exiting... (`whoami`)"
  rm -f "$TEMP_PASSWD_FILE"
  rm -f "$PGPASSFILE"
  exit 1
fi

if [[ `cat "$TEMP_PASSWD_FILE" | md5sum` != \
      `cat ~/data/conf/pool_passwd | md5sum` ]] ; then
  echo "Roles change in PostgreSQL, updating 'pool_passwd' (`whoami`)"
  cat "$TEMP_PASSWD_FILE" > ~/data/conf/pool_passwd
  reloadPgPool
fi

rm -f "$TEMP_PASSWD_FILE"
rm -f "$PGPASSFILE"

