#!/bin/bash

# Set of functions to extract information from
# the postgresql nodes setup on pgpool
# and make some configuration using pcp_* commands

# PCP configuration
pcp_host="pgpool.domain.com"
pcp_port="9898"
pcp_username="your_user"
pcp_password="your_password"
pcp_timeout="10"
pcp_path="/usr/sbin"

# PostgreSQL connection setup
export PGPASSWORD="postgres_passwd"
export PGCONNECT_TIMEOUT=2

# Health check uses psql to connect to each backend server. Specify options required to connect here
psql_healthcheck_opts="-U postgres"

# Default options to send to pcp commands
pcp_cmd_preamble="$pcp_timeout $pcp_host $pcp_port $pcp_username $pcp_password"

#
# Runs abitrary pcp command with the preamble
#
_pcp()
{
        cmd=$1
        shift
        $cmd $pcp_cmd_preamble $*
}

#
# Prints the total number of pgpool nodes.
#
_get_node_count()
{
        $pcp_path/pcp_node_count $pcp_cmd_preamble
}

# Prints out node information for the specified pgpool node
#
_get_node_info()
{
        if [ -z $1 ]; then
                echo "Usage: $0 _get_node_info <node id>" >&2
                return 99
        fi

        $pcp_path/pcp_node_info $pcp_cmd_preamble $1
}

#
# Outputs the replication lag (in bytes) between the specified master and slave
#
_get_replication_lag()
{
        if [ -z $2 ]; then
                echo "Usage: $0 _get_replication_lag <master node id> <slave node id>" >&2
                return 99
        fi

        # Get connection information for nodes
        master_node_info=($(_get_node_info $1))
        if [ $? -gt 0 ]; then
                echo "ERROR: Failed getting node info for node $1" >&2
                return 1
        fi
        slave_node_info=($(_get_node_info $2))
        if [ $? -gt 0 ]; then
                echo "ERROR: Failed getting node info for node $2" >&2
                return 1
        fi

        for n in $1 $2; do
                if [ $(_is_node_alive $n) -eq 0 ]; then
                        echo "ERROR: Node $n is not available. Unable to calculate lag." >&2
                        return 1
                fi
        done

        # Get xlog locations for master and slaves
        master_xlog_loc=$(psql $psql_healthcheck_opts -h "${master_node_info[0]}" -p "${master_node_info[1]}" -Atc "SELECT pg_current_xlog_location();")
        if [ $? -gt 0 ]; then
                echo "ERROR: Failed getting xlog location from node $1" >&2
                return 1
        fi
        slave_xlog_loc=$(psql $psql_healthcheck_opts -h "${slave_node_info[0]}" -p "${slave_node_info[1]}" -Atc "SELECT pg_last_xlog_replay_location();")
        if [ $? -gt 0 ]; then
                echo "ERROR: Failed getting xlog location from node $2" >&2
                return 1
        fi

        # Number of bytes behind
        echo $(($(_xlog_to_bytes $master_xlog_loc) - $(_xlog_to_bytes $slave_xlog_loc)))
}

#
# Converts specified xlog number to byte location
#
_xlog_to_bytes()
{
        if [ -z $1 ]; then
                echo "Usage: $0 _xlog_to_bytes <xlog loc>" >&2
                echo "  Eg.: $0 _xlog_to_bytes 0/2BC825C0" >&2
                return 99
        fi
        logid="${1%%/*}"
        offset="${1##*/}"
        echo $((0xFFFFFF * 0x$logid + 0x$offset))
}

#
# Prints whether the postgresql service on the specified node is responding.
#
_is_node_alive()
{
        if [ -z $1 ]; then
                echo "Usage: $0 _is_node_alive <node id>" >&2
                return 99
        fi

        # Get node connection information
        node_info=($(_get_node_info $1))

        if [ $? -gt 0 ]; then
                echo "ERROR: Failed getting node info for node $1" >&2
                return 1
        fi

        result=$(psql $psql_healthcheck_opts -h "${node_info[0]}" -p "${node_info[1]}" -Atc "SELECT 1;" 2>/dev/null)

        if [ "$result" == "1" ]; then
                echo 1
                return 1
        else
                echo 0
                return 0
        fi
}

#
# Get the node ID of the first master
#
_get_master_node()
{
        # Get total number of nodes
        nodes=$(_get_node_count)

        if [ $? -gt 0 ]; then
                echo "ERROR: Failed getting node count: $nodes" >&2
                exit 1
        fi

        c=0

        # Loop through each node to check if it's the master
        while [ $c -lt $nodes ]; do
                if [ "$(_is_standby $c)" == "0" ]; then
                        echo $c
                        return 0
                fi
                let c=c+1
        done

        echo "-1"
        return 1
}

#
# Checks if the node is in postgresql recovery mode (ie. if it is a slave)
#
_is_standby()
{
        if [ -z $1 ]; then
                echo "Usage: $0 _is_standby <node id>" >&2
                return 99
        fi

        # Get node connection information
        node_info=($(_get_node_info $1))

        if [ $? -gt 0 ]; then
                echo "ERROR: Failed getting node info for node $1" >&2
                return 1
        fi

        result=$(psql $psql_healthcheck_opts -h "${node_info[0]}" -p "${node_info[1]}" -Atc "SELECT pg_is_in_recovery();" 2>/dev/null)

        if [ "$result" == "t" ]; then
                echo 1
                return 1
        else
                echo 0
                return 0
        fi
}

#
# Attaches the specified node to the pool
#
_attach()
{
        if [ -z $1 ]; then
                echo "Usage: $0 attach <node id>" >&2
                return 99
        fi

        $pcp_path/pcp_attach_node $pcp_cmd_preamble $1
}

#
# Detaches the specified node from the pool
#
_detach()
{
        if [ -z $1 ]; then
                echo "Usage: $0 detach <node id>" >&2
                return 99
        fi
        $pcp_path/pcp_detach_node $pcp_cmd_preamble $1
}

#
# Recovers the specified node (restores it from current master and re-attaches)
#
_recover()
{
        if [ -z $1 ]; then
                echo "Usage: $0 recover <node id>" >&2
                return 99
        fi
        $pcp_path/pcp_recovery_node $pcp_cmd_preamble $1
}

#
# Prints the status of the specified node in human readable format.
#
_get_node_status()
{
        if [ -z $1 ]; then
                echo "Usage: $0 _get_node_status <node id>" >&2
                return 99
        fi

        node_info=($(_get_node_info $1))

        if [ $? -gt 0 ]; then
                echo "ERROR: Failed getting node info for node $1" >&2
        else
                node_role=""
                node_replication_lag=""
                node_alive=""
                case "$(_is_node_alive $1)" in
                        1)
                                node_alive="Up"
                                ;;
                        *)
                                node_alive="Down"
                                ;;
                esac
                if [ "$node_alive" == "Up" ]; then

                        # Find out what role this node has
                        if [ "$(_is_standby $1)" == "1" ]; then

                                node_role="Slave"

                                # Calculation replication lag
                                master_node=$(_get_master_node)
                                node_replication_lag=$(_get_replication_lag $master_node $1)
                                if [ $? -eq 0 ]; then
                                        node_replication_lag="$node_replication_lag bytes"
                                else
                                        node_replication_log="Unknown"
                                fi
                        else
                                node_role="Master"
                        fi
                fi
                case "${node_info[2]}" in
                        3)
                                node_status="detached from pool"
                                ;;
                        2)
                                node_status="in pool and connected"
                                ;;
                        1)
                                node_status="in pool"
                                ;;
                        *)
                                node_status="Unknown"
                                ;;
                esac

                # Print status information about this node
                echo "Node: $1"
                echo "Host: ${node_info[0]}"
                echo "Port: ${node_info[1]}"
                echo "Weight: ${node_info[3]}"
                echo "Status: $node_alive, $node_status (${node_info[2]})"
                [ -n "$node_role" ] && echo "Role: $node_role"
                [ -n "$node_replication_lag" ] && echo "Replication lag: $node_replication_lag"
                echo ""
        fi
}
