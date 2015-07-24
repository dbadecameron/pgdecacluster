#!/bin/bash
# -*- coding: utf-8 -*-
# 
# new-pgpool-node.sh
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
      ¿Generar llaves SSH? [S/n] "
read SURE_SSH

if [ "$SURE_SSH" == "S" ] ; then
    echoGreen "Creando llaves..."
    ssh-keygen -N "" \
               -C "$DBA_EMAIL" \
               -t rsa \
               -f /pgcluster/keys/id_rsa-pgcluster_$CLUSTER_NAME
else
    echoPurple "
      Se ha desactivado la generación de llaves SSH
      En este momento copie las llaves SSH del otro nodo en /pgcluster/keys
      Cuando este listo presione ENTER para continuar"
    read SURE
fi

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

echoGreen "Creando árbol de directorios base, usuarios, permisos y contextos... [pgpool-II]"
mkdir -p /pgcluster/pg$CLUSTER_NAME/pgpool/data
groupadd -g 2000$CLUSTER_ID pgpool$CLUSTER_NAME && 
useradd --gid pgpool$CLUSTER_NAME \
        --uid 2000$CLUSTER_ID \
        --home-dir /pgcluster/pg$CLUSTER_NAME/pgpool \
        -M pgpool$CLUSTER_NAME
usermod -a -G pggroup$CLUSTER_NAME pgpool$CLUSTER_NAME
chage -I -1 -m 0 -M 99999 -E -1 pgpool$CLUSTER_NAME
chown pgpool$CLUSTER_NAME:pgpool$CLUSTER_NAME /pgcluster/pg$CLUSTER_NAME/pgpool
chmod 750 /pgcluster/pg$CLUSTER_NAME/pgpool
    echo "
# Source global definitions
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi

export PATH=/opt/PostgresPlus/9.xAS/bin:\$PATH
export PGHOME=/opt/PostgresPlus/9.xAS
export PGLOCALEDIR=/opt/PostgresPlus/9.xAS/share/locale
export PGDATABASE=postgres
export PGUSER=postgres
export PGPORT=$BASE_PORT
" > /pgcluster/pg$CLUSTER_NAME/pgpool/.profile
chmod 644 /pgcluster/pg$CLUSTER_NAME/pgpool/.profile
chown pgpool$CLUSTER_NAME:pgpool$CLUSTER_NAME /pgcluster/pg$CLUSTER_NAME/pgpool/.profile

echo '#!/bin/bash

. ~/../globals.cfg

if [ -f ~/data/scripts/make-backup-from-master.sh ] ; then
  . ~/data/conf/misc.cfg

  for d in $DATABASES_TO_BACKUP ; do
    ~/data/scripts/make-backup-from-master.sh "$d"
  done
fi

exit 0' > /pgcluster/pg$CLUSTER_NAME/pgpool/make-db-backups.sh
chown pgpool$CLUSTER_NAME:pgpool$CLUSTER_NAME /pgcluster/pg$CLUSTER_NAME/pgpool/make-db-backups.sh
chmod +x /pgcluster/pg$CLUSTER_NAME/pgpool/make-db-backups.sh

mkdir -p /pgcluster/pg$CLUSTER_NAME/pgpool/.ssh
cat "/pgcluster/keys/id_rsa-pgcluster_$CLUSTER_NAME" > \
    /pgcluster/pg$CLUSTER_NAME/pgpool/.ssh/id_rsa
cat "/pgcluster/keys/id_rsa-pgcluster_$CLUSTER_NAME.pub" > \
    /pgcluster/pg$CLUSTER_NAME/pgpool/.ssh/id_rsa.pub
cat "/pgcluster/keys/id_rsa-pgcluster_$CLUSTER_NAME.pub" > \
    /pgcluster/pg$CLUSTER_NAME/pgpool/.ssh/authorized_keys
chmod 700 /pgcluster/pg$CLUSTER_NAME/pgpool/.ssh
chmod 600 /pgcluster/pg$CLUSTER_NAME/pgpool/.ssh/authorized_keys
chmod 600 /pgcluster/pg$CLUSTER_NAME/pgpool/.ssh/id_rsa
chmod 644 /pgcluster/pg$CLUSTER_NAME/pgpool/.ssh/id_rsa.pub
echo "$BACKUP_CRON_LINE ~/make-db-backups.sh" > /var/spool/cron/pgpool$CLUSTER_NAME
chown -R pgpool$CLUSTER_NAME:pgpool$CLUSTER_NAME /pgcluster/pg$CLUSTER_NAME/pgpool/.ssh
chown pgpool$CLUSTER_NAME:pgpool$CLUSTER_NAME /var/spool/cron/pgpool$CLUSTER_NAME
chmod 600 /var/spool/cron/pgpool$CLUSTER_NAME

echoGreen "Creando árbol de directorios base, usuarios, permisos y contextos... [Respaldos pg_dump]"
mkdir -p /pgcluster/pg$CLUSTER_NAME/backup
mkdir -p /pgcluster/pg$CLUSTER_NAME/backup/postgres
chown -R pgpool$CLUSTER_NAME:pgpool$CLUSTER_NAME /pgcluster/pg$CLUSTER_NAME/backup
chmod -R 700 /pgcluster/pg$CLUSTER_NAME/backup

echoGreen "Terminando de configurar SELinux..."
semanage fcontext -a -e "/var/lib/pgsql/.ssh" "/pgcluster/pg$CLUSTER_NAME/pgpool/.ssh"
semanage fcontext -a -e "/etc/httpd/conf" "/pgcluster/pg$CLUSTER_NAME/pgpool/data/pgpooladmin/httpd/conf"
semanage fcontext -a -e "/etc/httpd/conf.d" "/pgcluster/pg$CLUSTER_NAME/pgpool/data/pgpooladmin/httpd/conf.d"
semanage fcontext -a -e "/var/log/httpd" "/pgcluster/pg$CLUSTER_NAME/pgpool/data/pgpooladmin/httpd/logs"
semanage fcontext -a -e "/etc/httpd/modules" "/pgcluster/pg$CLUSTER_NAME/pgpool/data/pgpooladmin/httpd/modules"
semanage fcontext -a -e "/var/www" "/pgcluster/pg$CLUSTER_NAME/pgpool/data/pgpooladmin/httpd/var/www"
semanage fcontext -a -e "/var/www" "/pgcluster/pg$CLUSTER_NAME/pgpool/data/conf"
semanage fcontext -a -e "/var/log/httpd" "/pgcluster/pg$CLUSTER_NAME/pgpool/data/log"
semanage fcontext -a -e "/var/lib/php/session" "/pgcluster/pg$CLUSTER_NAME/pgpool/data/pgpooladmin/httpd/var/lib/php"

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


semanage boolean -m --on httpd_can_network_connect
restorecon -RF /opt
restorecon -RF /pgcluster
restorecon -RF /var/spool/cron
restorecon -RF /etc/logrotate.d

echoGreen "Recuerde copiar el directorio scripts a /pgcluster/scripts"

