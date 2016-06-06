# DARE

__DARE scalability__  
The second phase of log replication consists of three RDMA accesses. First, for each adjusted remote log, the leader writes all entries between the remote and the local tail pointers. Second, the leader updates the tail pointers of all the servers _for which the first access completed successfully_. To commit log entries, the leader sets the local commit pointer to the minimum tail pointer among at least a majority of servers (itself included). Finally, for the remote servers to apply the just committed entries, the leader “lazily” updates the remote commit pointers; _by lazy update we mean that there is no need to wait for completion_.  
![code illustration](https://github.com/wangchenghku/DARE/blob/master/figures/direct_log_update.png)  
  
rc_disconnect_server() disconnects both QPs for a given server, used for server removals.
