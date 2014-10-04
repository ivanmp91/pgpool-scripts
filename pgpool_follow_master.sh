#!/bin/bash
 
# Parameters
slave_node=$1
old_master_node=$2
new_master=$3
cluster_path=$4

# Load default pgpool functions
. lib/pgpool.sh

# Do nothing if the slave node passed is not in standby
if [ "$(_is_standby $slave_node)" != "1" ] ; then
	exit 0;
fi

# Get node information
node_info=($(_get_node_info $slave_node))
node_hostname=(${node_info[0]})
# Reconfigure slave node to point on the new master
/usr/bin/ssh -T $node_hostname -o "VerifyHostKeyDNS no" -o "StrictHostKeyChecking no" "perl -i -pe 's/host=\S*/host='$new_master'/' $cluster_path/recovery.conf"
# Restart slave node to take effect the new configuration
/usr/bin/ssh -T $node_hostname -o "VerifyHostKeyDNS no" -o "StrictHostKeyChecking no" "service postgresql restart > /dev/null"
# Attach slave node
_attach $slave_node
