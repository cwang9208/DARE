#!/bin/bash
#
# Copyright (c) 2014-2015 ETH-Zurich. All rights reserved.
#
# Author(s): Marius Poke <marius.poke@inf.ethz.ch>
#

########################################################################
###
# list of servers (see example below)
servers=(euler02 euler03 euler04 euler05 euler06 euler07 euler08 euler10)
###
# client (see example below)
client="euler11"
###
# info regarding where to get back the results 
port=10000
host="mpoke@localhost"
host_dir=/home/mpoke/dare/data/
###
# folder with DARE
DAREDIR=/mnt/SG/mpoke/repository/dare
########################################################################

declare -A pids
declare -A rounds
leader=""
client_pid=0
redirection=( "> out" "2> err" "< /dev/null" )

ErrorAndExit () {
    echo "ERROR: $1"
    StopLoop
    StopDare
    exit 1
}

StartDare() {
    for ((i=0; i<=$1-1; ++i));
    do
        run_dare=( "${DAREDIR}/bin/srv_test" "-l ${DAREDIR}/log.${servers[$i]}_1" "-n ${servers[$i]}" "-s $server_count" "-i $i" )
        cmd=( "ssh" "root@${servers[$i]}" "nohup" "${run_dare[@]}" "${redirection[@]}" "&" "echo \$!" )
        pids[${servers[$i]}]=$("${cmd[@]}")
        rounds[${servers[$i]}]=2
        #echo "COMMAND: "${cmd[@]}
    done
    echo -e "\n\tinitial servers: $leader: ${!pids[@]}"
    echo -e "\t...and their PIDs: ${pids[@]}"
}

StopDare() {
    for i in "${!pids[@]}"
    do
        cmd=( "ssh" "root@$i" "kill -s SIGINT" "${pids[$i]}" )
        echo "Executing: ${cmd[@]}"
        $("${cmd[@]}")
    done
    cmd=( "scp" "-P ${port}" "$data_file" "${host}:${host_dir}/events.data" )
    echo "Executing: ${cmd[@]}"
    $("${cmd[@]}")
}

FindLeader() {
    leader=""
    max_idx=-1
    max_term=""
    for i in "${!pids[@]}"
    do
        cmd=( "ssh" "root@$i" "grep \"LEADER (term\" $DAREDIR/log.${i}_$((rounds[$i]-1))" )
        #echo ${cmd[@]}
        grep_out=$("${cmd[@]}")
        if [[ -z $grep_out ]]; then
            continue
        fi
        terms=($(echo $grep_out | awk '{print $3}'))
        for j in "${terms[@]}"
        do
           if [[ $j > $max_term ]]; then 
                max_term=$j
                leader=$i
            fi
        done
        #echo "Leader=$leader"
    done
}

RemoveLeader() {
    FindLeader
    if [[ -z $leader ]]; then
        echo -e "\n\tNo leader [$leader]"
        return 1
    fi
    #echo ${!pids[@]}
    #echo ${pids[@]}
    if [[ -z ${pids[$leader]} ]]; then
        echo -e "\n\tNo PID for the leader $leader"
        return 1
    fi
    cmd=( "ssh" "root@$leader" "kill -s SIGINT" "${pids[$leader]}" )
    $("${cmd[@]}")
    unset pids[$leader]
    echo -e "\n\tservers after removing $leader: ${!pids[@]}"
    echo -e "\t...and their PIDs: ${pids[@]}"
    #echo ${cmd[@]}
    maj=$(bc -l <<< "$1/2.")
    if [[ ${#pids[@]} < $maj ]]; then
        ErrorAndExit "...not enough servers!"
    fi
    return 0
}

# Stop a server that is not the leader
RemoveServer() {
    FindLeader
    echo -e "\n\tleader: $leader"
    for i in "${!pids[@]}"
    do
        if [[ "x$i" == "x$leader" ]]; then
            continue
        fi
        cmd=( "ssh" "root@$i" "kill -s SIGINT" "${pids[$i]}" )
        echo -e "\tcmd: ${cmd[@]}"
        $("${cmd[@]}")
        unset pids[$i]
        echo -e "\tservers after removing $i: ${!pids[@]}"
        echo -e "\t...and their PIDs: ${pids[@]}"
        #echo ${cmd[@]}
        break
    done
    maj=$(bc -l <<< "$1/2.")
    if [[ ${#pids[@]} < $maj ]]; then
        ErrorAndExit "...not enough servers!"
    fi
}

AddServer() {
    if [[ ${#pids[@]} == $server_count ]]; then
        # the group is full
        server_count=$((server_count+2))
    fi
    for i in "${servers[@]}"
    do
        next=0
        for j in "${!pids[@]}"
        do 
            if [[ "x$i" == "x$j" ]]; then
               next=1
               break
            fi
        done
        if [[ $next == 1 ]]; then
            continue
        fi
        break
    done
    if [[ "x${rounds[$i]}" == "x" ]]; then
        rounds[$i]=1
    fi
    #run_dare=( "${DAREDIR}/bin/srv_test" "${DAREDIR}/log.${i}_${rounds[$i]}" "$i" )
    run_dare=( "${DAREDIR}/bin/srv_test" "-l ${DAREDIR}/log.${i}_${rounds[$i]}" "--join" "-n $i" )
    cmd=( "ssh" "root@$i" "nohup" "${run_dare[@]}" "${redirection[@]}" "&" "echo \$!" )
    #echo ${cmd[@]}
    pids[$i]=$("${cmd[@]}")
    rounds[$i]=$((rounds[$i] + 1))
    #echo $i
    echo -e "\n\tservers after adding $i: ${!pids[@]}"
    echo -e "\t...and their PIDs: ${pids[@]}"
}

# Resize the group to $1
DareGroupResize() {
    if [ $1 -gt $server_count ]; then
        ErrorAndExit "To increase the group size, add a server."
    fi
    cmd=( "${DAREDIR}/bin/clt_test" "--reconf" "-s $1" )
    #echo ${cmd[@]}
    ${cmd[@]}
    if [ $1 -lt $server_count ]; then 
        # downsize: unset pids of removed servers
        for ((i=$1; i<$server_count; ++i)); do
            unset pids[${servers[$i]}]
        done        
    fi
    server_count=$1
    echo -e "\n\tservers after resizing: ${!pids[@]}"
    echo -e "\t...and their PIDs: ${pids[@]}"
}

StartLoop() {
    cmd=( "rm -f $trace_file" )
    ${cmd[@]}
    cmd=( "${DAREDIR}/bin/kvs_trace" "--loop" "--${op}" "-s ${blob_size}" "-o $trace_file" )
    #echo "Executing: ${cmd[@]}"
    ${cmd[@]}
    run_loop=( "${DAREDIR}/bin/clt_test" "--loop" "-t $trace_file" "-o $data_file" "-l ${DAREDIR}/log.$client" )
    cmd=( "ssh" "root@$client" "nohup" "${run_loop[@]}" "${redirection[@]}" "&" "echo \$!" )
    #echo "Executing: ${cmd[@]}"
    client_pid=$("${cmd[@]}")
}

StopLoop() {
    cmd=( "ssh" "root@$client" "kill -s SIGINT" "$client_pid" )
    echo "Executing: ${cmd[@]}"
    $("${cmd[@]}")
}

########################################################################

Stop() {
    sleep 0.5
    StopLoop
    sleep 0.2
    StopDare
    exit 1
}

Start() {
    echo -ne "Starting $server_count servers..."
    StartDare $server_count
    echo "done"

    sleep 2

    StartLoop

    sleep 0.5
    
    if [[ "x$1" == "xstop" ]]; then
        Stop
    fi    
}

FailLeader() {
    echo -ne "Removing the leader..."
    while true; do
        RemoveLeader $server_count
        ret=$?
        #echo "ret=$ret"
        if [ $ret -eq 0 ]; then 
            break;    
        fi
        sleep 0.05
    done
    echo "done"

    sleep 1
    
    if [[ "x$1" == "xstop" ]]; then
        Stop
    fi  
}

RecoverServer() {
    echo -ne "Adding a server..."
    AddServer
    echo "done"

    sleep 0.5
    
    if [[ "x$1" == "xstop" ]]; then
        Stop
    fi
}

Upsize() {
    echo -ne "Adding a server (upsize)..."
    AddServer
    echo "done"

    sleep 0.3
    
    if [[ "x$1" == "xstop" ]]; then
        Stop
    fi
}

Downsize() {
    size=$((server_count - 2))
    echo -ne "Resize group from $server_count to $size..."
    DareGroupResize $size
    echo "done"

    sleep 0.3
    
    if [[ "x$1" == "xstop" ]]; then
        Stop
    fi
}

FailServer() {
    echo -ne "Removing a server (non-leader)..."
    RemoveServer $server_count
    echo "done"

    sleep 0.7
    
    if [[ "x$1" == "xstop" ]]; then
        Stop
    fi
}

########################################################################

# Get the number of initial servers 
if [[ "x$1" == "x" ]]; then
    ErrorAndExit "Usage: $0 <#servers> <put|get> <size (8-1024)>"
fi
server_count=$1
if [ $server_count -gt ${#servers[@]} -o $server_count -lt 0 ] ; then
    ErrorAndExit "0 <= #servers <= ${#servers[@]}"
fi
if [ "x$2" != "xput" -a "x$2" != "xget" ]; then
    ErrorAndExit "Usage: $0 <#servers> <put|get> <size (8-1024)>"
fi
if [[ "x$3" == "x" ]]; then
    ErrorAndExit "Usage: $0 <#servers> <put|get> <size (8-1024)>"
fi
if [ $3 -gt 2048 -o $3 -lt 8 ] ; then
    ErrorAndExit "Usage: $0 <#servers> <put|get> <size (8-1024)>"
fi
op=$2
blob_size=$3
data_file="${DAREDIR}/loop_${op}_${blob_size}b.data"
trace_file="${DAREDIR}/loop_${op}_${blob_size}b.trace"

# Handle SIGINT to ensure a clean exit
trap 'echo -ne "Stop all servers..." && StopLoop && StopDare && echo "done" && exit 1' INT

# Remove previous log files
rm -f log.*

########################################################################

# Start DARE (size = 5)
Start

#Stop

# Remove the leader (size = 6)
#FailLeader 

#sleep 1

#Stop

# Upsize (size = 6)
Upsize

# Upsize (size = 7)
Upsize 

#sleep 2
#Stop

# Remove the leader (size = 6)
FailLeader

# Remove a server that is not the leader (size = 5)
FailServer 

# Add a server (size = 6)
RecoverServer

# Add a server (size = 7)
RecoverServer 

# Downsize (size = 5)
Downsize 

# Remove the leader (size = 4)
FailLeader 

# Add a server (size = 5)
RecoverServer

# Downsize (size = 3)
Downsize stop

########################################################################


