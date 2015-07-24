#!/bin/bash -x
# -*- coding: utf-8 -*-
# 
# follow_master_command.sh
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

#
# Execute command by failover.
# special values:  %d = node id
#                  %h = host name
#                  %p = port number
#                  %D = database cluster path
#                  %m = new master node id
#                  %M = old master node id
#                  %H = new master node host name
#                  %P = old primary node id
#                  %r = New master port number.
#                  %R = New master database cluster directory.
#                  %% = '%' character

. ~/../globals.cfg
. ~/data/conf/misc.cfg
. /pgcluster/scripts/funcs

failed_node_id=$(($1 + 1))
failed_host_name=$2
failed_port=$3
failed_db_cluster=$4
new_master_id=$(($5 + 1))
old_master_id=$(($6 + 1))
new_master_host_name=$7
old_primary_node_id=$(($8 + 1))
new_master_port=$9
new_master_db_cluster=${10}

PG_CTL=/opt/PostgresPlus/9.xAS/bin/pg_ctl
PSQL=/opt/PostgresPlus/9.xAS/bin/psql
PCP_ATTACH_NODE=/opt/PostgresPlus/9.xAS/bin/pcp_attach_node

if [ $# != 10 ]; then
  echo "Usage: $(basename $0) failed_node_id failed_host_name failed_port failed_db_cluster new_master_id old_master_id new_master_host_name old_primary_node_id new_master_port new_master_db_cluster" >&2
  exit 1
fi

> /tmp/followmaster-pguser$CLUSTER_NAME$failed_node_id.log
chmod 'u=rw,g=,o=' /tmp/followmaster-pguser$CLUSTER_NAME$failed_node_id.log
(

set -e
if [ $failed_node_id = $old_primary_node_id ]; then # old master follow
  set +e
fi
export PGPASSFILE=`mktemp -t tmp.\`whoami\`.XXXXXXXXXX`
chmod 'u=rw,g=,o=' "$PGPASSFILE"
echo \
  "$failed_host_name:$failed_port:template1:$PGPOOL_USER:$PGPOOL_PASSWORD" > \
  "$PGPASSFILE"
set +e
$PSQL -p $failed_port -h $failed_host_name -U $PGPOOL_USER -c "SELECT pg_xlog_replay_pause();" -w template1
rm -f "$PGPASSFILE"
unset PGPASSFILE

ssh -oStrictHostKeyChecking=no -n -T -l pguser$CLUSTER_NAME$failed_node_id $failed_host_name "$PG_CTL stop -w -m fast -D $failed_db_cluster"
set -e
ssh -oStrictHostKeyChecking=no -T -l pguser$CLUSTER_NAME$failed_node_id $failed_host_name "rm -f $failed_db_cluster/make_me_master"
ssh -oStrictHostKeyChecking=no -T -l pguser$CLUSTER_NAME$failed_node_id $failed_host_name "rm -f $failed_db_cluster/recovery.done"

# make recovery.conf for slave host
cat <<EOL | ssh -oStrictHostKeyChecking=no -T -l pguser$CLUSTER_NAME$failed_node_id $failed_host_name "cat > $failed_db_cluster/recovery.conf"
standby_mode = 'on'
primary_conninfo = 'user=$REPLICATION_USER host=$new_master_host_name port=$new_master_port sslmode=prefer sslcompression=1 krbsrvname=postgres'
trigger_file = '$failed_db_cluster/make_me_master'
recovery_target_timeline='latest'
EOL

WAL_RECEIVER_BEFORE=`ssh -oStrictHostKeyChecking=no -T -l pguser$CLUSTER_NAME$failed_node_id $failed_host_name "ps ux | grep wal | grep -v grep | grep 'wal receiver process[[:space:]]*streaming' | wc -l"`
ssh -oStrictHostKeyChecking=no -n -T -l pguser$CLUSTER_NAME$failed_node_id $failed_host_name "$PG_CTL restart -W -m fast -D $failed_db_cluster > /dev/null 2>&1 < /dev/null &"
sleep $(($failed_node_id * 2 + 5))
WAL_RECEIVER_AFTER=`ssh -oStrictHostKeyChecking=no -T -l pguser$CLUSTER_NAME$failed_node_id $failed_host_name "ps ux | grep wal | grep -v grep | grep 'wal receiver process[[:space:]]*streaming' | wc -l"`
let WAL_RECEIVER_COUNT=WAL_RECEIVER_AFTER-WAL_RECEIVER_BEFORE
if [ $WAL_RECEIVER_COUNT == "1" ] ; then
 # No se recomienda atachar los nodos, detalles en bug:
 # http://www.pgpool.net/mantisbt/view.php?id=121
 ATTACH_MSG="NO se"
 if [ -f ~/data/conf/attach_nodes ] ; then
  $PCP_ATTACH_NODE 3 $PGPOOL_SERVER $PCP_PORT $PCP_USERNAME $PCP_PASSWORD $((failed_node_id - 1))
  ATTACH_MSG="Se ha"
 fi
 echo "
Se ha logrado notificar satisfactoriamente a uno de los nodos esclavos
sobre la promoción del nuevo maestro. $ATTACH_MSG ha retornado a pgpool-II.
Por favor retorne el nodo al pool de balanceo sólo cuando este se
encuentre sincronizado con el maestro.

Detalles:

ID del nodo notificado: $failed_node_id
Nodo notificado: $failed_host_name
Puerto del nodo notificado: $failed_port
Directorio de datos del nodo notificado: $failed_db_cluster
WAL_RECEIVER_COUNT=$WAL_RECEIVER_COUNT

ID del nodo maestro: $failed_node_id
Nodo maestro: $failed_host_name
Puerto del nodo maestro: $failed_port
Directorio de datos del nodo maestro: $failed_db_cluster

" | mail -s "[pgcluster] Notificada promoción a nodo esclavo" \
            "$DBA_EMAIL"
else
 set +e
 ssh -oStrictHostKeyChecking=no -n -T -l pguser$CLUSTER_NAME$failed_node_id $failed_host_name "$PG_CTL stop -w -m fast -D $failed_db_cluster"
 echo "
No se logró notificar satisfactoriamente a uno de los nodos sobre
la promoción del nuevo maestro. Le recomendamos validar el estado de
salud del nodo y si es necesario, correr un proceso de recovery del
nodo.

Se ha detenido el esclavo como medida de seguridad.

Detalles:

ID del nodo notificado: $failed_node_id
Nodo notificado: $failed_host_name
Puerto del nodo notificado: $failed_port
Directorio de datos del nodo notificado: $failed_db_cluster
WAL_RECEIVER_COUNT=$WAL_RECEIVER_COUNT

ID del nodo maestro: $failed_node_id
Nodo maestro: $failed_host_name
Puerto del nodo maestro: $failed_port
Directorio de datos del nodo maestro: $failed_db_cluster

" | mail -s "[pgcluster] ERROR notificando esclavo sobre promoción" \
            "$DBA_EMAIL"

fi

exit 0
) > /tmp/followmaster-pguser$CLUSTER_NAME$failed_node_id.log 2>&1 &

exit 0

