#!/bin/bash
#
# Copyright (c) 2014-2015 ETH-Zurich. All rights reserved.
#
# Author(s): Marius Poke <marius.poke@inf.ethz.ch>
#

########################################################################
###
# list of servers (see example below)
servers=(euler03 euler04 euler05)
###
# list of clients (see example below)
clients=(euler01 euler02 euler06 euler07 euler08 euler09 euler10 euler11 euler12)
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
declare -A cpids
declare -A data_files
leader=""
redirection=( "> out" "2> err" "< /dev/null" )

ErrorAndExit () {
    echo "ERROR: $1"
    StopClients
    StopDare
    exit 1
}

StartDare() {
    for ((i=0; i<=$1-1; ++i));
    do
        run_dare=( "${DAREDIR}/bin/srv_test" "-l ${DAREDIR}/log.${servers[$i]}_1" "-n ${servers[$i]}" "-s $server_count" "-i $i" )
        cmd=( "ssh" "root@${servers[$i]}" "nohup" "${run_dare[@]}" "${redirection[@]}" "&" "echo \$!" )
        pids[${servers[$i]}]=$("${cmd[@]}")
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
}

StartClients() {
    # Create trace file - the same for each client
    cmd=( "rm -f $trace_file" )
    echo "Executing: ${cmd[@]}"
    ${cmd[@]}
    cmd=( "${DAREDIR}/bin/kvs_trace" "--loop" "--${op}" "-s ${blob_size}" "-o $trace_file" )
    echo "Executing: ${cmd[@]}"
    ${cmd[@]}
    for i in "${!clients[@]}"; do
        if [[ "x${proc}" == "x" ]]; then
            data_files[${clients[$i]}]="${DAREDIR}/loop_req_${op}_${blob_size}b_c${i}.data"
            run_loop=( "${DAREDIR}/bin/clt_test" "--loop" "-t $trace_file" "-o ${data_files[${clients[$i]}]}" "-l ${DAREDIR}/log.${clients[$i]}" )
        else 
            data_files[${clients[$i]}]="${DAREDIR}/loop_req_${op}_p${proc}_${blob_size}b_c${i}.data"
            run_loop=( "${DAREDIR}/bin/clt_test" "--loop" "-t $trace_file" "-p $proc" "-o ${data_files[${clients[$i]}]}" "-l ${DAREDIR}/log.${clients[$i]}" )
        fi
        cmd=( "ssh" "root@${clients[$i]}" "nohup" "${run_loop[@]}" "${redirection[@]}" "&" "echo \$!" )
        echo "Executing: ${cmd[@]}"
        cpids[${clients[$i]}]=$("${cmd[@]}")
        sleep 1
    done
}

StopClients() {
    tmp=( ${!cpids[@]} )
    IFS=$'\n' sorted_cpids=($(sort <<<"${tmp[*]}"))
    for i in "${sorted_cpids[@]}"
    do
        cmd=( "ssh" "root@$i" "kill -s SIGINT" "${cpids[$i]}" )
        echo "Executing: ${cmd[@]}"
        $("${cmd[@]}")
    done
    for i in "${sorted_cpids[@]}"
    do
        cmd=( "scp" "-P ${port}" "${data_files[$i]}" "${host}:${host_dir}" )
        echo "Executing: ${cmd[@]}"
        $("${cmd[@]}")
    done
}

########################################################################

# Get the number of initial servers 
if [[ "x$1" == "x" ]]; then
    ErrorAndExit "Usage: $0 <#servers> <put|get> <size (8-1024)> <1st_op_proc (0-100)>"
fi
if [ $server_count -gt ${#servers[@]} -o $server_count -lt 0 ] ; then
    ErrorAndExit "0 <= #servers <= ${#servers[@]}"
fi
if [ "x$2" != "xput" -a "x$2" != "xget" ]; then
    ErrorAndExit "Usage: $0 <#servers> <put|get> <size (8-1024)> <1st_op_proc (0-100)>"
fi
if [[ "x$3" == "x" ]]; then
    ErrorAndExit "Usage: $0 <#servers> <put|get> <size (8-1024)> <1st_op_proc (0-100)>"
fi
if [ $3 -gt 2048 -o $3 -lt 8 ] ; then
    ErrorAndExit "Usage: $0 <#servers> <put|get> <size (8-1024)> <1st_op_proc (0-100)>"
fi
if [[ "x$4" != "x" ]]; then
    proc=$4
    if [ $4 -gt 100 -o $4 -lt 0 ] ; then
    ErrorAndExit "Usage: $0 <#servers> <put|get> <size (8-1024)> <1st_op_proc (0-100)>"
    fi
fi

op=$2
blob_size=$3
trace_file="${DAREDIR}/loop_req_${op}_${blob_size}b.trace"

# Handle SIGINT to ensure a clean exit
trap 'echo -ne "Stop all servers..." && StopClients && StopDare && echo "done" && exit 1' INT

# Remove previous log files
rm -f log.*
########################################################################

echo -ne "Starting $server_count servers..."
StartDare $server_count
echo "done"

sleep 2

# Write entry in the SM
tmp_tfile="${DAREDIR}/_tmp.trace"
tmp_dfile="${DAREDIR}/_tmp.data"
cmd=( "${DAREDIR}/bin/kvs_trace" "--loop" "--put" "-s ${blob_size}" "-o ${tmp_tfile}" )
${cmd[@]}
cmd=( "${DAREDIR}/bin/clt_test" "--trace" "-t $tmp_tfile" "-o $tmp_dfile" "-l ${DAREDIR}/log.tmp" )
${cmd[@]}
rm ${DAREDIR}/log.tmp ${tmp_tfile} ${tmp_dfile}

StartClients
StopClients

sleep 0.2
StopDare

########################################################################


