#!/bin/bash
# Recovery script for streaming replication.
# This script assumes that DB node 0 is primary, and 1 is standby.
#
datadir=$1 #eg: /var/lib/postgresql/9.3/main/
desthost=$2 #slave's ip

#prepare for a local backup
psql -c "SELECT pg_start_backup('Streaming Replication', true)" postgres

#prepare remote postgres server for slave-ification
ssh postgres@$desthost -o "VerifyHostKeyDNS no" -o "StrictHostKeyChecking no" "/etc/init.d/postgresql stop > /dev/null ; rm /var/tmp/postgresql.trigger > /dev/null 2>&1  ; rm $datadir/recovery.done > /dev/null 2>&1"

# Creates recovery config file for the new slave
ssh postgres@$desthost -o "VerifyHostKeyDNS no" -o "StrictHostKeyChecking no" "cat > $datadir/recovery.conf <<EOF
standby_mode = on
trigger_file = '/var/tmp/postgresql.trigger'
primary_conninfo = 'host=`hostname -f` port=5432 user=postgres password=P@ssw0rd'
recovery_target_timeline='latest'
EOF"

#copy local data to remove postgres server
rsync -C -a --delete -e 'ssh -o "VerifyHostKeyDNS no" -o "StrictHostKeyChecking no"' --exclude pg_log --exclude pg_xlog --exclude recovery.conf --exclude recovery.done --exclude postgresql.conf --exclude pg_hba.conf --exclude postmaster.opts --exclude postmaster.pid --exclude server.crt --exclude server.key $datadir/ $desthost:$datadir/

#this archives the the WAL log (ends writing to it and moves it to the $archive dir
psql -c "SELECT pg_stop_backup()" postgres

#this rsyncs the WAL archives that are written after pg_stop_backup is called.
rsync -C -a --delete -e 'ssh -o "VerifyHostKeyDNS no" -o "StrictHostKeyChecking no"' $datadir/pg_xlog/ $desthost:$datadir/pg_xlog/
