# DARE

Direct log update.  
The second phase of log replication consists of three RDMA accesses. First, for each adjusted remote log, the leader writes all entries between the remote and the local tail pointers. Second, the leader updates the tail pointers of all the servers **for which the first access completed successfully**. To commit log entries, the leader sets the local commit pointer to the minimum tail pointer among at least a majority of servers (itself included). Finally, for the remote servers to apply the just committed entries, the leader “lazily” updates the remote commit pointers; **by lazy update we mean that there is no need to wait for completion**.
