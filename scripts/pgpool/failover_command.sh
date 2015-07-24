#!/bin/bash -x
# -*- coding: utf-8 -*-
# 
# failover_command.sh
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

set -e

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
trigger=$new_master_db_cluster/make_me_master

PSQL=/opt/PostgresPlus/9.xAS/bin/psql
PG_CTL="/opt/PostgresPlus/9.xAS/bin/pg_ctl"

echo "`getPgpoolNodesInfoPCP`"

if [ $# != 10 ]; then
  echo "Usage: $(basename $0) failed_node_id failed_host_name failed_port failed_db_cluster new_master_id old_master_id new_master_host_name old_primary_node_id new_master_port new_master_db_cluster" >&2
  exit 1
fi

set +e
if [ -f ~/data/conf/custom-failover_command ] &&
   [ -x ~/data/conf/custom-failover_command ] ; then 
  ( exec -c ~/data/conf/custom-failover_command $* ) \
    >> ~/data/log/custom-failover_command.log 2>&1 &
fi
set -e

if [ $failed_node_id = $old_primary_node_id ]; then # master failed
  ( set +e ; isolateNode $(($new_master_id - 1)) ) &
  sleep 10
  ssh -oStrictHostKeyChecking=no -T pguser$CLUSTER_NAME$new_master_id@$new_master_host_name "$PG_CTL -w -m fast -D $new_master_db_cluster restart < /dev/null >& /dev/null"
  sleep 3
  ssh -oStrictHostKeyChecking=no -T pguser$CLUSTER_NAME$new_master_id@$new_master_host_name $PG_CTL -D $new_master_db_cluster promote # let standby take over
  msg="
El nodo maestro ha fallado, se ha desligado del cluster y se ha promovido
otro nodo para que cumpla este rol. Por favor intervenga lo antes posible,
el cluster se encuentra en un estado de degradacion ALTA.

Los datos de la operacion son los siguientes:

ID del nodo degradado: $failed_node_id
Nodo degradado: $failed_host_name
Puerto del nodo degradado: $failed_port
Directorio de datos del nodo degradado: $failed_db_cluster

ID del nodo promovido: $new_master_id
Nodo promovido: $new_master_host_name

===============
FIN DEL MENSAJE
"
  subject="[pgcluster] Falla en nodo master, cluster muy degradado"
else
  msg="
Uno de los nodos del cluster ha fallado, este se ha desligado del cluster. 
Por favor intervenga, el cluster se encuentra degradado.

Los datos del evento son los siguientes:

ID del nodo desligado: $failed_node_id
Nodo desligado: $failed_host_name
Puerto del nodo desligado: $failed_port
Directorio de datos del nodo desligado: $failed_db_cluster

===============
FIN DEL MENSAJE
"
  subject="[pgcluster] Falla en un nodo, cluster degradado"
fi

echo "$msg" | mail -s "$subject" "$DBA_EMAIL"

