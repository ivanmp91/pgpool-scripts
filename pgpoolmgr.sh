#!/bin/bash
#
# pgpool-II replication manager
#
# Interfaces with pgpool's pcp command-line tools to provide access to common functions for managing
# load-balancing and failover.
#

. lib/pgpool.sh

#
# Attaches the specified node to the pool
#
attach()
{
	_attach $1
}

#
# Detaches the specified node from the pool
#
detach()
{
	_detach $1
}

#
# Recovers the specified node (restores it from current master and re-attaches)
#
recover()
{
	_recover $1
}

#
# Prints out the status of all pgpool nodes in human readable form.
#
status()
{
	# Get total number of nodes
	nodes=$(_get_node_count)

	if [ $? -gt 0 ]; then
		echo "ERROR: Failed getting node count: $nodes" >&2
		exit 1
	fi

	c=0

	# Loop through each node to retrieve info
	while [ $c -lt $nodes ]; do
		_get_node_status $c
		let c=c+1
	done
}

# Run function
if [ ! "$(type -t $1)" ]; then
	echo "Usage $0 <option>" >&2
	echo "" >&2
	echo "Available options:" >&2
	echo "$(compgen -A function |grep -v '^_')" >&2
	exit 99
else
	cmd=$1
	shift
	$cmd $*

	exit $?
fi

