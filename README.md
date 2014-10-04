pgpool-scripts
==============

Set of scripts for pgpool-II:

- basebackup.sh : located on the root of the database cluster path for postgresql and is used to initialize new nodes and for the online recovery process.
- failover_stream.sh : Used to create the trigger file on the new master server in event of failover.
- pgpool_follow_master.sh : Setup on pgpool with the parameter follow_master_command. This script is run after the event of failover to reconfigure the postgresql slave nodes and point to the new master of the cluster.
- pgpool_remote_start : located on the root of the database cluster path for postgresql and is used to start the postgresql daemon on a remote host.
- pgpoolmgr.sh : Script used to show the status of the pgpool nodes, recover, attach or detach nodes on the cluster. It's just an interface which uses pcp commands.

pgpoolmgr.sh and lib/pgpool.sh functions are got from that script https://gist.github.com/dansimau/1582492
