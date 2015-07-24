#!/bin/bash
# -*- coding: utf-8 -*-
# 
# terminate-idle-backends.sh
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

PG_USERNAME=`getPgPoolConf recovery_user`
PG_PASSWORD=`getPgPoolConf recovery_password`

for BNAME in `grep "^backend_hostname" ~/data/conf/pgpool.conf | 
              sed 's/\(backend_hostname[0-9]\+\).*/\1/g'` ; do
  PNAME=`echo $BNAME | sed 's/backend_hostname/backend_port/g'`
  PG_HOSTNAME=`getPgPoolConf $BNAME`
  PG_PORT=`getPgPoolConf $PNAME`

  export PGPASSFILE=`mktemp -t tmp.\`whoami\`.XXXXXXXXXX`
  chmod 'u=rw,g=,o=' "$PGPASSFILE"
  echo \
   "$PG_HOSTNAME:$PG_PORT:template1:$PG_USERNAME:$PG_PASSWORD" > \
   "$PGPASSFILE"

  psql -h "$PG_HOSTNAME" \
       -U "$PG_USERNAME" \
       -p "$PG_PORT" \
       -F" " \
       -A \
       -t \
       -c "SELECT pg_terminate_backend(pg_stat_activity.pid)
           FROM pg_stat_activity
           WHERE pg_stat_activity.state='idle'
           AND application_name<>'pg_dump'
           AND pid <> pg_backend_pid();" \
       template1

  rm -f "$PGPASSFILE" > /dev/null 2>&1
done

