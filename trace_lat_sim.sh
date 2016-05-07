#!/bin/bash
#
# Copyright (c) 2014-2015 ETH-Zurich. All rights reserved.
#
# Author(s): Marius Poke <marius.poke@inf.ethz.ch>
#

########################################################################
###
# list of servers (see example below)
servers=(euler02 euler03 euler04 euler05 euler06 euler08 euler10)
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
redirection=( "> out" "2> err" "< /dev/null" )

ErrorAndExit () {
    echo "ERROR: $1"
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
        #echo ${cmd[@]}
    done
    cmd=( "scp" "-P ${port}" "$data_file" "${host}:${host_dir}/events.data" )
    echo "Executing: ${cmd[@]}"
    $("${cmd[@]}")
}

########################################################################

# Get the number of initial servers 
if [[ "x$1" == "x" ]]; then
    ErrorAndExit "Usage: $0 <#servers> <put|get>"
fi
server_count=$1
if [ $server_count -gt ${#servers[@]} -o $server_count -lt 0 ] ; then
    ErrorAndExit "0 <= #servers <= ${#servers[@]}"
fi
if [ "x$2" != "xput" -a "x$2" != "xget" ]; then
    ErrorAndExit "Usage: $0 <#servers> <put|get>"
fi
op=$2
data_file="${DAREDIR}/trace_lat_${op}_g${server_count}.data"
trace_file="${DAREDIR}/trace_lat_${op}_g${server_count}.trace"

# Handle SIGINT to ensure a clean exit
trap 'echo -ne "Stop all servers..." && StopDare && echo "done" && exit 1' INT

# Remove previous log files
rm -f log.*

########################################################################

echo -ne "Starting $server_count servers..."
StartDare $server_count
echo "done"

sleep 8

cmd=( "rm -f $trace_file" )
${cmd[@]}
cmd=( "${DAREDIR}/bin/kvs_trace" "--trace" "--${op}" "-o $trace_file" )
#echo "Executing: ${cmd[@]}"
${cmd[@]}
cmd=( "${DAREDIR}/bin/clt_test" "--rtrace" "-t $trace_file" "-o $data_file" "-l ${DAREDIR}/log.$HOSTNAME" )
echo "Executing: ${cmd[@]}"
${cmd[@]}

StopDare

########################################################################


