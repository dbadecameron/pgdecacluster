#!/bin/bash -x
# -*- coding: utf-8 -*-
# 
# make-backup-from-master.sh
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

BACKUP_PATH=/pgcluster/pg$CLUSTER_NAME/backup/postgres

EXPECTED_MIN_ARGS=1
EXPECTED_MAX_ARGS=1
E_BADARGS=65
BASE_NAME=`basename $0`

if [[ $# -gt $EXPECTED_MAX_ARGS ]] || 
   [[ $# -lt $EXPECTED_MIN_ARGS ]] || 
   [[ $1 == "--help" ]] ; then
  echo "Usage: $BASE_NAME <database>" 1>&2
  echo "       $BASE_NAME --help" 1>&2
  exit $E_BADARGS
fi

MASTER_NODE_FILE=`mktemp -t tmp.\`whoami\`.XXXXXXXXXX`
chmod 'u=rw,g=,o=' "$MASTER_NODE_FILE"

trap exit SIGINT SIGTERM ERR
getPgpoolNodesInfo | grep "primary$" > "$MASTER_NODE_FILE"
trap '' SIGINT SIGTERM ERR

export PGPASSFILE=`mktemp -t tmp.\`whoami\`.XXXXXXXXXX`
chmod 'u=rw,g=,o=' "$PGPASSFILE"

MASTER_ID=`cat "$MASTER_NODE_FILE" | awk -F"$FIELD_SEPARATOR" '{print $1}'`
MASTER_HOSTNAME=`cat "$MASTER_NODE_FILE" | awk -F"$FIELD_SEPARATOR" '{print $2}'`
MASTER_PORT=`cat "$MASTER_NODE_FILE" | awk -F"$FIELD_SEPARATOR" '{print $3}'`
BLABEL="$1-`date '+%Y-%m-%d_%H'`-node_$MASTER_ID"
PG_USERNAME=`getPgPoolConf recovery_user`
PG_PASSWORD=`getPgPoolConf recovery_password`

echo "$MASTER_HOSTNAME:$MASTER_PORT:$1:$PG_USERNAME:$PG_PASSWORD" \
  > "$PGPASSFILE"

START_DATE=`date`
pg_dump -f "$BACKUP_PATH/$BLABEL.dump" \
        -h "$MASTER_HOSTNAME" \
        -p "$MASTER_PORT" \
        -U "$PG_USERNAME" \
        -Z 9 \
        -F c \
        -v \
        -w \
        "$1" 2>&1 | gzip > "$BACKUP_PATH/$BLABEL.log.gz" 
END_DATE=`date`

sha512sum "$BACKUP_PATH/$BLABEL.dump" > "$BACKUP_PATH/$BLABEL.dump.sha512sum"

rsync -e "ssh -T -oStrictHostKeyChecking=no" \
      -avzhP "$BACKUP_PATH/$BLABEL.dump" \
             "$BACKUP_USER@$BACKUP_SERVER:$REMOTE_BACKUP_PATH"

if [ $? == 0 ] ; then
  rm -f $BACKUP_PATH/$BLABEL.dump
  RSYNC_OK_MSG="Archivo sincronizado satisfactoriamente en 
$BACKUP_SERVER, por tanto fue borrado $BACKUP_PATH/$BLABEL.dump."
else
  RSYNC_OK_MSG="NO SE PUDO SINCRONIZAR EL ARCHIVO EN $BACKUP_SERVER
EL ARCHIVO $BACKUP_PATH/$BLABEL.dump NO FUE BORRADO. INTERVENGA."
fi

echo "

$RSYNC_OK_MSG

Reporte del proceso de respaldo
===============================

BD: $1
Fecha de inicio: $START_DATE
Fecha de fin: $END_DATE
ID del nodo: $(($MASTER_ID + 1))
Hostname del nodo: $MASTER_HOSTNAME
Puerto del nodo: $MASTER_PORT
Etiqueta: $BLABEL
Suma de verificacion (SHA-512): `cat "$BACKUP_PATH/$BLABEL.dump.sha512sum"`


Mensajes finales
================

`zcat "$BACKUP_PATH/$BLABEL.log.gz" | tail`


df -h
=====

`df -h`


df -i
=====

`df -i`



===============
FIN DEL MENSAJE
" | mail -s "[pgcluster] Reporte del repaldo de $1" "$BACKUP_EMAIL"

rsync -e "ssh -T -oStrictHostKeyChecking=no" \
      -avzhP "$BACKUP_PATH/$BLABEL.log.gz" \
             "$BACKUP_PATH/$BLABEL.dump.sha512sum" \
             "$BACKUP_USER@$BACKUP_SERVER:$REMOTE_BACKUP_LOG_PATH"

if [ $? == 0 ] ; then
  rm -f $BACKUP_PATH/$BLABEL.log.gz
fi

rm -f "$MASTER_NODE_FILE"
rm -f "$PGPASSFILE"

