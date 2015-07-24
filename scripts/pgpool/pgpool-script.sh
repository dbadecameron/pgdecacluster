#!/bin/bash
#
# Modified from pgpool-HA
# http://www.pgpool.net/mediawiki/index.php/Downloads
#

pushd `dirname $0` > /dev/null
SCRIPT_PATH=`pwd`
popd > /dev/null

pushd "$SCRIPT_PATH/../../../"
. ./globals.cfg
popd
pushd "$SCRIPT_PATH/../conf/"
. ./misc.cfg
popd

. /pgcluster/scripts/funcs

##### Source function library.

. /usr/share/cluster/ocf-shellfuncs
. /usr/share/cluster/utils/config-utils.sh
. /usr/share/cluster/utils/messages.sh
. /usr/share/cluster/utils/ra-skelet.sh

###### Parameter defaults

OCF_RESOURCE_INSTANCE=pgpool-script-pgpool$CLUSTER_NAME
OCF_RESKEY_pgpoolconf_default="/pgcluster/pg$CLUSTER_NAME/pgpool/data/conf/pgpool.conf"
OCF_RESKEY_pcpconf_default="/pgcluster/pg$CLUSTER_NAME/pgpool/data/conf/pcp.conf"
OCF_RESKEY_hbaconf_default="/pgcluster/pg$CLUSTER_NAME/pgpool/data/conf/pool_hba.conf"
OCF_RESKEY_logfile_default="/pgcluster/pg$CLUSTER_NAME/pgpool/data/log/pgpool.log"
OCF_RESKEY_options_default=""
OCF_RESKEY_pgpooluser_default="pgpool$CLUSTER_NAME"
OCF_RESKEY_checkmethod_default="pid"
OCF_RESKEY_checkstring_default="/pgcluster/pg$CLUSTER_NAME/pgpool/data/run/pgpool.pid"

if [ "$USE_EDB" == "0" ] ; then
    OCF_RESKEY_pgpoolcmd_default=/usr/pgpool-$PG_VERSION/bin/pgpool
    OCF_RESKEY_psqlcmd_default=/usr/bin/psql
    OCF_RESKEY_pcpnccmd_default=/usr/bin/pcp_node_count
else
    OCF_RESKEY_pgpoolcmd_default=/opt/PostgresPlus/9.xAS/bin/pgpool
    OCF_RESKEY_psqlcmd_default=/opt/PostgresPlus/9.xAS/bin/psql
    OCF_RESKEY_pcpnccmd_default=/opt/PostgresPlus/9.xAS/bin/pcp_node_count
fi

: ${OCF_RESKEY_pgpoolconf=${OCF_RESKEY_pgpoolconf_default}}
: ${OCF_RESKEY_pcpconf=${OCF_RESKEY_pcpconf_default}}
: ${OCF_RESKEY_hbaconf=${OCF_RESKEY_hbaconf_default}}
: ${OCF_RESKEY_logfile=${OCF_RESKEY_logfile_default}}
: ${OCF_RESKEY_options=${OCF_RESKEY_options_default}}
: ${OCF_RESKEY_pgpooluser=${OCF_RESKEY_pgpooluser_default}}
: ${OCF_RESKEY_checkmethod=${OCF_RESKEY_checkmethod_default}}
: ${OCF_RESKEY_checkstring=${OCF_RESKEY_checkstring_default}}
: ${OCF_RESKEY_pgpoolcmd=${OCF_RESKEY_pgpoolcmd_default}}
: ${OCF_RESKEY_psqlcmd=${OCF_RESKEY_psqlcmd_default}}
: ${OCF_RESKEY_pcpnccmd=${OCF_RESKEY_pcpnccmd_default}}

if [ ! -e $OCF_RESKEY_pgpoolconf ]; then
	ocf_log warn "${OCF_RESOURCE_INSTANCE}: file '$OCF_RESKEY_pgpoolconf' (pgpoolconf) does not exists."
fi

PIDFILE=$(cat "$OCF_RESKEY_pgpoolconf" | grep "^pid_file_name" | cut -d "'" -f 2)

if [ "x$OCF_RESKEY_checkstring" = "x" ] ; then
	case "$OCF_RESKEY_checkmethod" in
	pcp)
		OCF_RESKEY_checkstring="10 localhost 9898 postgres pass" ;;
	psql)
		OCF_RESKEY_checkstring="-h localhost -U postgres -p 9999 -l" ;;
	esac
else
	case "$OCF_RESKEY_checkmethod" in
	pid)
		PIDFILE=$OCF_RESKEY_checkstring ;;
	esac
fi

###### Build Start command

PGPOOL="$OCF_RESKEY_pgpoolcmd -f $OCF_RESKEY_pgpoolconf" 
PGPOOL_START_ARG=""

if [ "x$OCF_RESKEY_hbaconf" != 'x' ]; then
	PGPOOL="$PGPOOL -a $OCF_RESKEY_hbaconf"
fi
if [ "x$OCF_RESKEY_pcpconf" != 'x' ]; then
	PGPOOL="$PGPOOL -F $OCF_RESKEY_pcpconf"
fi
if [ "x$OPTIONS" != 'x' ]; then
	PGPOOL_START_ARG="$PGPOOL_START_ARG $OPTIONS"
fi
if [ "x$OCF_RESKEY_logfile" != 'x' ]; then
	PGPOOL="nohup $PGPOOL"
	if [ $(echo $OCF_RESKEY_logfile | cut -c 1) = '|' ]; then
		PGPOOL_START_ARG="$PGPOOL_START_ARG -n 2>&1 $OCF_RESKEY_logfile &"
	else
		PGPOOL_START_ARG="$PGPOOL_START_ARG -n >> $OCF_RESKEY_logfile 2>&1 &"
	fi
fi

PGPOOL_STOP_ARG=" -m fast stop"

###### Functions

do_monitor() {
	if ! pidfile_process_exists_p 
	then
		return $OCF_NOT_RUNNING
	fi

	case "$OCF_RESKEY_checkmethod" in
	pid)
		return $OCF_SUCCESS
		;;
	pcp)
		do_pcp_check
		return $?
		;;
	psql)
		do_psql_check
		return $?
		;;
	esac
	ocf_log err "${OCF_RESOURCE_INSTANCE}: Invalid checkmethod parameter"
	return $OCF_ERR_GENERIC
}


do_pcp_check() {
	ocf_run -q $OCF_RESKEY_pcpnccmd $OCF_RESKEY_checkstring
	rc=$?
	if [ $rc -eq 0 ]
	then
		return $OCF_SUCCESS
	else
		ocf_log err "${OCF_RESOURCE_INSTANCE}: pcp_check fail"
		return $OCF_NOT_RUNNING
	fi
}


do_psql_check() {
	ocf_run -q $OCF_RESKEY_psqlcmd $OCF_RESKEY_checkstring
	rc=$?
	if [ $rc -eq 0 ]
	then
		return $OCF_SUCCESS
	else
		ocf_log err "${OCF_RESOURCE_INSTANCE}: psql_check fail"
		return $OCF_NOT_RUNNING
	fi
}


do_start() {
	if pidfile_process_exists_p 
	then 
		ocf_log info "${OCF_RESOURCE_INSTANCE}: pgpool is already running."
		return $OCF_SUCCESS
	fi

	ocf_log info \
		"${OCF_RESOURCE_INSTANCE}: ~/data/scripts/terminate-idle-backends.sh AS $OCF_RESKEY_pgpooluser"
	su $OCF_RESKEY_pgpooluser -c "~/data/scripts/terminate-idle-backends.sh"
	ocf_log info \
		"${OCF_RESOURCE_INSTANCE}: $PGPOOL $PGPOOL_START_ARG AS $OCF_RESKEY_pgpooluser"
	su $OCF_RESKEY_pgpooluser -c "$PGPOOL $PGPOOL_START_ARG"
	if [ $? -ne 0 ]
	then
		ocf_log err "${OCF_RESOURCE_INSTANCE}: Can't start pgpool."
		return $OCF_ERR_GENERIC
	fi

	return $OCF_SUCCESS
}


do_stop() {
	if ! pidfile_process_exists_p
	then
		ocf_log info "${OCF_RESOURCE_INSTANCE}: pgpool is already stopped."
		return $OCF_SUCCESS
	fi

	su -c "$PGPOOL $PGPOOL_STOP_ARG"
	if [ $? -ne 0 ]
	then
		ocf_log err "${OCF_RESOURCE_INSTANCE}: Can't stop pgpool."
		return $OCF_ERR_GENERIC
	fi

	while pidfile_process_exists_p ; do
		ocf_log debug "${OCF_RESOURCE_INSTANCE}: not stopped yet, waiting"
		sleep 1
	done

	return $OCF_SUCCESS
}


do_reload() {
	su -c "$PGPOOL reload"
	return $OCF_SUCCESS
}


# - has side effect: kills zombie immediately 
# - dependency: /proc/PID/status file
#
pidfile_process_exists_p() {
	if [ -f $PIDFILE ]; then
		RPID=`cat $PIDFILE`
		if kill -0 $RPID
		then
			if grep -E "^State:.*zombie" /proc/$RPID/status
			then
				pkill -QUIT -P $RPID
				kill -QUIT $RPID
				return 1
			else
				return 0   # ok, process exists
			fi
		else
			return 1
		fi
	else
		ocf_log debug "${OCF_RESOURCE_INSTANCE}: PIDFILE $PIDFILE doesn't exist"
		return 1
	fi
}


do_metadata() {
	cat <<EOF
<?xml version="1.0"?>
<!DOCTYPE resource-agent SYSTEM "ra-api-1.dtd">
<resource-agent name="pgpool">
 <version>${VERSION}</version>
 <longdesc lang="en">
This is an OCF Resource Agent for pgpool-II.
 </longdesc>
 <shortdesc lang="en">OCF Resource Agent for pgpool-II</shortdesc>
 <parameters>
  <parameter name="pgpoolconf" unique="0" required="0">
   <longdesc lang="en">
Path to pgpool.conf of pgpool.
   </longdesc>
   <shortdesc lang="en">pgpool.conf path</shortdesc>
   <content type="string" default="$OCF_RESKEY_pgpoolconf_default" />
  </parameter>
  <parameter name="pcpconf" unique="0" required="0">
   <longdesc lang="en">
Path to pcp.conf of pgpool.
   </longdesc>
   <shortdesc lang="en">pcp.conf path</shortdesc>
   <content type="string" default="$OCF_RESKEY_pcpconf_default" />
  </parameter>
  <parameter name="hbaconf" unique="0" required="0">
   <longdesc lang="en">
Path to pool_hba.conf of pgpool.
   </longdesc>
   <shortdesc lang="en">pool_hba.conf path</shortdesc>
   <content type="string" default="$OCF_RESKEY_hbaconf_default" />
  </parameter>
  <parameter name="logfile" unique="0" required="0">
   <longdesc lang="en">
pgpool log file for stdout and stderr redirection;
or a program for log collecting by a pipeline.
(e.g.)
 "/var/log/pgpool.log"
 "| logger -t pgpool -p local3.info"
   </longdesc>
   <shortdesc lang="en">pgpool logfile</shortdesc>
   <content type="string" default="$OCF_RESKEY_logfile_default" />
  </parameter>
  <parameter name="options" unique="0" required="0">
   <longdesc lang="en">
pgpool command line options (except configuration file options).
   </longdesc>
   <shortdesc lang="en">pgpool command line options</shortdesc>
   <content type="string" default="$OCF_RESKEY_options_default" />
  </parameter>
  <parameter name="pgpooluser" unique="0" required="0">
   <longdesc lang="en">
pgpool run as this user.
   </longdesc>
   <shortdesc lang="en">pgpool user</shortdesc>
   <content type="string" default="$OCF_RESKEY_pgpooluser_default" />
  </parameter>
  <parameter name="checkmethod" unique="0" required="0">
   <longdesc lang="en">
monitoring method type.
 "pid"  process existence check only.
 "pcp"  check by pcp_node_count command.
 "psql" check by psql command.
   </longdesc>
   <shortdesc lang="en">monitoring method type</shortdesc>
   <content type="string" default="$OCF_RESKEY_checkmethod_default" />
  </parameter>
  <parameter name="checkstring" unique="0" required="0">
   <longdesc lang="en">
parameter for monitoring method.
when checkmetod="pid", this means pidfile path.
  (e.g.) "/var/run/pgpool/pgpool.pid"
when checkmetod="pcp", this means a parameter string for pcp_node_count.
  (e.g.) "10 localhost 9898 postgres pass"
when checkmetod="psql", this means a parameter string for psql.
  (e.g.) "-U postgres -h localhost -l -p 9999"
   </longdesc>
   <shortdesc lang="en">a parameter for monitoring method</shortdesc>
   <content type="string" default="$OCF_RESKEY_checkstring_default" />
  </parameter>
  <parameter name="pgpoolcmd" unique="0" required="0">
   <longdesc lang="en">
pgpool command.
   </longdesc>
   <shortdesc lang="en"></shortdesc>
   <content type="string" default="$OCF_RESKEY_pgpoolcmd_default" />
  </parameter>
  <parameter name="psqlcmd" unique="0" required="0">
   <longdesc lang="en">
psql command.
   </longdesc>
   <shortdesc lang="en">psql command</shortdesc>
   <content type="string" default="$OCF_RESKEY_psqlcmd_default" />
  </parameter>
  <parameter name="pcpnccmd" unique="0" required="0">
   <longdesc lang="en">
pcp_node_count command.
   </longdesc>
   <shortdesc lang="en">pcp_node_count command</shortdesc>
   <content type="string" default="$OCF_RESKEY_pcpnccmd_default" />
  </parameter>
 </parameters>
 <actions>
  <action name="start" timeout="20" />
  <action name="stop" timeout="20" />
  <action name="monitor" depth="0" timeout="20" interval="10" />
  <action name="reload" timeout="20" />
  <action name="meta-data" timeout="5" />
  <action name="validate-all" timeout="5" />
 </actions>
</resource-agent>
EOF
	return $OCF_SUCCESS
}


do_help() {
	echo "pgpool (start|stop|reload|monitor|meta-data|validate-all|help)"
	return $OCF_SUCCESS
}


do_validate_all() {
	if [ "x$OCF_RESKEY_pgpoolconf" = "x" ] ; then
		return $OCF_ERR_CONFIGURED
	fi
	if [ ! -e $OCF_RESKEY_pgpoolconf ] ; then
		return $OCF_ERR_CONFIGURED
	fi
	if [ ! -x $OCF_RESKEY_pgpoolcmd ] ; then
		return $OCF_ERR_INSALLED
	fi
	if [ ! -x $OCF_RESKEY_psqlcmd -a $OCF_RESKEY_checkmethod = "psql" ] ; then
		return $OCF_ERR_INSALLED
	fi
	if [ ! -x $OCF_RESKEY_pcpnccmd -a $OCF_RESKEY_checkmethod = "pcp" ] ; then
		return $OCF_ERR_INSALLED
	fi
	if [ "x$PIDFILE" = "x" -a $OCF_RESKEY_checkmethod = "pid" ]
	then
		return $OCF_ERR_CONFIGURED
	fi
	return $OCF_SUCCESS
}

###### main

case "$1" in
	start)
		do_validate_all && do_start ;;
	stop)
		do_stop  ;;
	reload)
		do_reload  ;;
	monitor|status)
		do_monitor ;;
	meta-data)
		do_metadata ;;
	promote|demote|migrate_to|migrate_from)
		exit $OCF_ERR_UNIMPLEMENTED ;;
	validate-all)
		do_validate_all ;;
	usage|help)
		do_help ;;
esac
RC=$?

ocf_log debug "${OCF_RESOURCE_INSTANCE}: $1 returned $RC"

exit $RC
