#!/bin/bash -x
# -*- coding: utf-8 -*-
# 
# recovery_1st_stage.sh
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

> /tmp/restore-$USER.log
chmod 'u=rw,g=,o=' /tmp/restore-$USER.log
(
LOCAL_PGDATA="$1"
REMOTE_IP="$2"
REMOTE_PGDATA="$3"
. $LOCAL_PGDATA/pgpool/scripts/config
. /pgcluster/scripts/funcs

set -e

PG_CTL="/opt/PostgresPlus/9.xAS/bin/pg_ctl"
PG_ISREADY="/opt/PostgresPlus/9.xAS/bin/pg_isready"

if ssh -oStrictHostKeyChecking=no -T -l $REMOTE_USERNAME $REMOTE_IP \
  $PG_CTL -D $REMOTE_PGDATA status | grep -q "server is running" ; then
  echo "Proceso anulado..."
  echo "
Se ha cancelado el recovery debido a que al parecer la instancia 
a recuperar esta corriendo, por favor verifique.

Proceso anulado para evitar posible corrupcion y perdida de informacion, 
INTERVENGA.

Nodo maestro: $LOCAL_IP
Nodo a sincronizar: $REMOTE_IP

" | mail -s "[pgcluster] Anulado proceso de recuperacion del nodo" \
            "$DBA_EMAIL"
    
  exit 1
fi

if ssh -T -l $REMOTE_USERNAME \
          -oStrictHostKeyChecking=no \
          $REMOTE_IP $PG_ISREADY -h $LOCAL_IP \
                                 -p $LOCAL_PORT \
                                 -U $PGPOOL_USER \
                                 -d template1 ; then
  echo "Inicando respaldo base..."
  ssh -T -l $REMOTE_USERNAME \
      -oStrictHostKeyChecking=no \
      $REMOTE_IP \
      "ln -s /pgcluster/scripts/postgres/pgpool/scripts/run-safe-pg_basebackup.sh ~/.run-safe-pg_basebackup-DELETEME.sh"
  ssh -T -l $REMOTE_USERNAME \
      -oStrictHostKeyChecking=no \
      $REMOTE_IP \
      "~/.run-safe-pg_basebackup-DELETEME.sh" "$REPLICATION_USER" "$LOCAL_PORT" "$LOCAL_IP" "$REMOTE_PGDATA"
  ssh -T -l $REMOTE_USERNAME \
      -oStrictHostKeyChecking=no \
      $REMOTE_IP \
      rm -f "~/.run-safe-pg_basebackup-DELETEME.sh" "~/.run-safe-pg_basebackup-DELETEME.sh.lock"

  echo "trigger_file = '$REMOTE_PGDATA/make_me_master'" | 
  ssh -oStrictHostKeyChecking=no -T -l $REMOTE_USERNAME $REMOTE_IP \
     "cat >> $REMOTE_PGDATA/recovery.conf"

  ssh -oStrictHostKeyChecking=no -T -l $REMOTE_USERNAME $REMOTE_IP \
      sed -i "\"s/^listen_addresses.*/listen_addresses = '$REMOTE_IP'/g;
                s/^port .*/port = '$REMOTE_PORT'/g\"" $REMOTE_PGDATA/postgresql.conf

  ssh -oStrictHostKeyChecking=no -T -l $REMOTE_USERNAME $REMOTE_IP \
      rm -f $REMOTE_PGDATA/make_me_master

  exit 0
fi

exit 1
) > /tmp/restore-$USER.log 2>&1

