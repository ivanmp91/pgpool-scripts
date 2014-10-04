#!/bin/bash

# Parameters
failed_node=$1
new_master=$2
trigger_file=$3

. lib/pgpool.sh

# Do nothing if failed node is not the master
if [ "$(_get_master_node)" != "$failed_node" ] ; then
	exit 0;
fi

# Create the trigger file on the new master
/usr/bin/ssh -T $new_master -o "VerifyHostKeyDNS no" -o "StrictHostKeyChecking no" /bin/touch $trigger_file

exit 0;
