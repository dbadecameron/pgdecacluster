#!/bin/bash
# -*- coding: utf-8 -*-
# 
# new-edbppas-node.sh
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

pushd `dirname $0` > /dev/null
SCRIPT_PATH=`pwd`
popd > /dev/null

. "$SCRIPT_PATH/config.cfg"

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

echoPurple "
      ¿Seguro que quiere continuar con la ejecución? [S/n] "
read SURE

if [ "$SURE" != "S" ] ; then
    exit 1
fi

mkdir -p /pgcluster/utils
mkdir -p /pgcluster/scripts
mkdir -p /pgcluster/keys
chmod 750 /pgcluster/keys

echoPurple "
      En este momento copie las llaves SSH del otro nodo en /pgcluster/keys
      Cuando este listo presione ENTER para continuar"
read SURE

echoPurple "Configurando cluster [$CLUSTER_NAME]..."

mkdir -p /pgcluster/pg$CLUSTER_NAME
groupadd -g "1"$(($CLUSTER_ID - 1))"000" pggroup$CLUSTER_NAME

echo "# Parametros globales para pgcluster
PATH=/opt/PostgresPlus/9.xAS/bin:\$PATH
PGLOCALEDIR=/opt/PostgresPlus/9.xAS/share/locale
DBA_EMAIL='$DBA_EMAIL'
BACKUP_EMAIL='$BACKUP_EMAIL'
CLUSTER_NAME='$CLUSTER_NAME'
BASE_PORT='$BASE_PORT'
BACKUP_USER='$BACKUP_USER'
BACKUP_SERVER='$BACKUP_SERVER'
REMOTE_BACKUP_PATH='$REMOTE_BACKUP_PATH'
REMOTE_BACKUP_LOG_PATH='$REMOTE_BACKUP_LOG_PATH'
PGPOOL_USER='<<CHANGE_ME>>'
PGPOOL_PASSWORD='<<CHANGE_ME>>'
PGPOOL_SERVER='<<CHANGE_ME>>'
REPLICATION_USER='<<CHANGE_ME>>'
PCP_USERNAME='<<CHANGE_ME>>'
PCP_PASSWORD='<<CHANGE_ME>>'
PCP_PORT='<<CHANGE_ME>>'
FIELD_SEPARATOR='{{}}'
" > /pgcluster/scripts/globals.cfg_$CLUSTER_NAME
chown root:pggroup$CLUSTER_NAME /pgcluster/scripts/globals.cfg_$CLUSTER_NAME
chmod 640 /pgcluster/scripts/globals.cfg_$CLUSTER_NAME
cat "$SCRIPT_PATH/config.cfg" > /pgcluster/scripts/config.cfg_$CLUSTER_NAME
ln -s /pgcluster/scripts/globals.cfg_$CLUSTER_NAME /pgcluster/pg$CLUSTER_NAME/globals.cfg

echoGreen "Creando árbol de directorios base, usuarios, permisos y contextos... [EnterpriseDB PPAS]"

mkdir -p /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID
mkdir -p /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.ssh
mkdir -p /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/data
mkdir -p /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/xlog
mkdir -p /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/wal_archive
semanage fcontext -a -e "/var/lib/pgsql/.ssh" "/pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.ssh"
semanage fcontext -a -e "/var/lib/pgsql/data" "/pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/data/pgdata"
groupadd -g "1"$(($CLUSTER_ID - 1))"00"$NODE_ID pguser$CLUSTER_NAME$NODE_ID &&
useradd --gid pguser$CLUSTER_NAME$NODE_ID \
        --uid "1"$(($CLUSTER_ID - 1))"00"$NODE_ID \
        --home-dir /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID \
        -M pguser$CLUSTER_NAME$NODE_ID
usermod -a -G pggroup$CLUSTER_NAME pguser$CLUSTER_NAME$NODE_ID
chage -I -1 -m 0 -M 99999 -E -1 pguser$CLUSTER_NAME$NODE_ID
cat "/pgcluster/keys/id_rsa-pgcluster_$CLUSTER_NAME" > \
    /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.ssh/id_rsa
cat "/pgcluster/keys/id_rsa-pgcluster_$CLUSTER_NAME.pub" > \
    /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.ssh/id_rsa.pub
cat "/pgcluster/keys/id_rsa-pgcluster_$CLUSTER_NAME.pub" > \
    /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.ssh/authorized_keys
echo "
# Source global definitions
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi

export PATH=/opt/PostgresPlus/9.xAS/bin:$PATH
export PGHOME=/opt/PostgresPlus/9.xAS
export PGLOCALEDIR=/opt/PostgresPlus/9.xAS/share/locale
export PGDATA=/pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/data/pgdata
export PGDATABASE=postgres
# export PGUSER=postgres
export PGPORT=$BASE_PORT$NODE_ID
" > /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.profile
echo "* * * * * /pgcluster/scripts/postgres/check_postgres_handler.sh" > /var/spool/cron/pguser$CLUSTER_NAME$NODE_ID
chmod 644 /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.profile
chmod 750 /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID
chmod 700 /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.ssh
chmod 600 /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.ssh/authorized_keys
chmod 600 /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.ssh/id_rsa
chmod 644 /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.ssh/id_rsa.pub
chown -R pguser$CLUSTER_NAME$NODE_ID:pguser$CLUSTER_NAME$NODE_ID /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.ssh
chown pguser$CLUSTER_NAME$NODE_ID:pguser$CLUSTER_NAME$NODE_ID /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/.profile
chown pguser$CLUSTER_NAME$NODE_ID:pguser$CLUSTER_NAME$NODE_ID /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID
chown pguser$CLUSTER_NAME$NODE_ID:pguser$CLUSTER_NAME$NODE_ID /pgcluster/pg$CLUSTER_NAME/pg$NODE_ID/wal_archive

echo "
/pgcluster/pg$CLUSTER_NAME/pgpool/data/log/*log {
    missingok
    compress
    copytruncate
    daily
    rotate 7
    notifempty
    olddir rotate
}

/pgcluster/pg$CLUSTER_NAME/pg*/data/misc/reports/pg_cluster_check.log {
    missingok
    compress
    copytruncate
    daily
    rotate 7
    notifempty
    olddir rotate
}
" > /pgcluster/utils/logrotate.$CLUSTER_NAME
cat /pgcluster/utils/logrotate.$CLUSTER_NAME > /etc/logrotate.d/pgcluster_$CLUSTER_NAME
chmod 644 /etc/logrotate.d/pgcluster_$CLUSTER_NAME

echoGreen "Finalizando configuración..."

echo '# -*- coding: utf-8 -*-
#
# pgcluster.py
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

import sos.plugintools

class pgcluster(sos.plugintools.PluginBase):
    """pgcluster related information
    """

    def checkenabled(self):
        self.files = [ "/pgcluster/scripts/funcs" ]
        return sos.plugintools.PluginBase.checkenabled(self)

    def setup(self):
        self.addCopySpec("/pgcluster/scripts/config.cfg_*")
        self.addCopySpec("/pgcluster/scripts/globals.cfg_*")
        self.addCopySpec("/pgcluster/pg*/pg*/data/pgdata/pg_log")
        self.addCopySpec("/pgcluster/pg*/pgpool/data/log")

' > /usr/lib/python2.6/site-packages/sos/plugins/pgcluster.py

restorecon -RF /opt
restorecon -RF /pgcluster
restorecon -RF /var/spool/cron
restorecon -RF /etc/logrotate.d

echoGreen "Recuerde copiar el directorio scripts a /pgcluster/scripts"

