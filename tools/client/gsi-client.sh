#!/bin/bash
#
# Copyright (c) Microsoft Corporation. All rights reserved.
#
# collect Lustre client info for troubleshooting.  As of 1/8/2024 commands run to collect logs:
    # uname -a
    # cat /etc/os-release
    # uptime; uptime -p
    # top -b -n1 
    # netstat -rn
    # netstat -Wan
    # ifconfig -a
    # printenv
    # lfs --version
    # lfs df -h --lazy; lfs df -hi --lazy
    # lfs check all
    # lfs getname
    # sudo dmesg -T
    # sudo sysctl -a
    # sudo lnetctl stats show
    # sudo lnetctl net show
    # sudo lnetctl peer show
    # sudo lnetctl global show
    # sudo lnetctl export
    # sudo lctl --net tcp conn_list
    # sudo lctl list_nids
    # sudo lctl ping nids
    # sudo lctl dl -t
    # mount -t lustre; mount
    # cat /etc/fstab |egrep lustre; cat /etc/fstab
    # sudo lctl dk dump_kernel
    # find /var/crash -ls
    # cat $read_ahead_kb
    # lfs quota -hv $local_lustre_mount
    # extracting vm vmSize and sku from file /run/cloud-init/instance-data.json
    # cat /run/cloud-init/instance-data.json
    # cd /var/log; tail -30 syslog
    # cd /var/log; tar cvfz $logdir/$clientgsidir/syslog.tgz syslog*
    # cd /var/log; sudo tail -30 messages
    # cd /var/log; sudo tar cvfz $logdir/$clientgsidir/messages.tgz messages*
    
usage() {
    echo "Usage ${0##*/} [options]"
    echo "collect lustre info"
    echo "  -l <log dir> starting dir for client-gsi-<date/time> dir.  Default to $HOME"
    echo "  -s Display hsm_state of all files.  May be very time consuming.  Skip is default."
    echo "  -h help"
    exit
}

main() {
    logdir=$HOME
    while getopts "hl:s" arg; do
        case $arg in
            h)
                usage
                ;;
            l)
                logdir="$OPTARG"
                ;;
            s)
                run_hsm_state=1
                ;;
            *)
                exit
                ;;
        esac
    done
    
    check_prerequisites # call subroutine to verify client can run the script
    
    clientgsidir="client-gsi-$(date +"%FT%T")"
    echo "$clientgsidir"
    cd "$logdir" || exit
    mkdir "$clientgsidir"
    cd "$clientgsidir" || exit
    log="$logdir"/"$clientgsidir"/gsi_client.log
    echo "$(date +"%FT%T"): Starting gsi_client.sh cpature." > "$log"
    echo "$(date +"%FT%T"): client gsi dir: " "$clientgsidir" >> "$log"
    command_divider "uname -a"
    uname -a |tee uname_a >> "$log"
    command_divider "cat /etc/os-release"
    tee release  >> "$log" < /etc/os-release
    command_divider "uptime; uptime -p"
    uptime |tee uptime >> "$log"; uptime -p |tee -a uptime >> "$log"
    command_divider "top -b -n1; top -b -n1 |head -20"
    top -b -n1 > top_output
    top -b -n1 |head -20 >> "$log"

    find_vm_sku # call subroutine to find the azure sku for the vm
    
    command_divider "netstat -rn"
    netstat -rn |tee netstat_rn >> "$log"
    command_divider "netstat -Wan"
    netstat -Wan > netstat_Wan
    command_divider "ifconfig -a"
    ifconfig -a 2>&1 |tee ifconfig_a >> "$log"
    command_divider "printenv"
    printenv |tee printenv >> "$log"
    # lfs commands
    command_divider "lfs --version"
    lfs --version |tee lfs_version >> "$log"
    command_divider "lfs df -h --lazy; lfs df -hi --lazy" # --lazy will allow command to run if an OST is having problems.
    {
    echo "lfs df -h (bytes)" | tee lfs_df
    lfs df -h --lazy |tee -a lfs_df
    echo "lfs df -hi (inodes)" |tee -a lfs_df
    lfs df -hi --lazy |tee -a lfs_df
     } >> "$log"
    command_divider "lfs check all"
    lfs check all 2>&1 |tee lfs_check_all >> "$log"
    command_divider "lfs getname"
    lfs getname 2>&1 |tee lfs_getname >> "$log"

    get_logs # subroutine to get syslog or messages files

    command_divider "sudo dmesg -T"
    sudo dmesg -T |tee dmesg > /dev/null
    command_divider "sudo sysctl -a"
    sudo sysctl -a | tee sysctl > /dev/null
    command_divider "sudo lnetctl global show"
    sudo lnetctl global show |tee lnetctl_global >> "$log"
    command_divider "sudo lnetctl stats show"
    sudo lnetctl stats show |tee lnetctl_stats >> "$log"
    command_divider "sudo lnetctl net show -v"
    sudo lnetctl net show -v |tee lnetctl_net >> "$log"
    command_divider "sudo lnetctl peer show -v"
    sudo lnetctl peer show -v |tee lnetctl_peer >> "$log"
    command_divider "sudo lnetctl export"
    sudo lnetctl export |tee lnetctl_export >> "$log"
    command_divider "sudo lctl list_nids"
    sudo lctl list_nids |tee lctl_list_nids >> "$log"
    command_divider "lctl ping nids"
    network=$(sudo lctl list_nids |cut -d@ -f2)
    # for i in $(sudo lctl --net tcp peer_list |cut -d- -f2 |cut -d" " -f1 |sort) ; do echo "nid: $i"; sudo lctl ping $i 2>&1 ; echo " " ; done |tee pingnids >> raylogs
    for nid in $(sudo lctl --net "$network" peer_list |cut -d- -f2 |cut -d" " -f1 |sort) 
    do 
        # echo "nid: $nid" |tee lctl_ping_nids >> "$log"
        echo "nid: $nid"
        #sudo lctl ping "$nid" 2>&1 |tee -a lctl_ping_nids >> "$log"
        sudo lctl ping "$nid" 2>&1
        echo " "
    done | tee lctl_ping_nids >> "$log"
    command_divider "sudo lctl dl -t"
    sudo lctl dl -t |tee lctl_dl >> "$log"
    command_divider "sudo lctl --net $network conn_list |sort"
    sudo lctl --net "$network" conn_list |sort |tee lctl_conn_list >> "$log"
    command_divider "mount -t lustre; mount"
    mount -t lustre |tee mount_output >> "$log"; mount >> mount_output
    if [ -f /etc/fstab ]
    then
        command_divider "cat /etc/fstab |egrep lustre; cat /etc/fstab"
        grep -E lustre < /etc/fstab |tee fstab >> "$log"
        tee -a fstab < /etc/fstab >> "$log"
    else
        command_divider "No /etc/fstab file."
    fi
    secure_boot=$(mokutil --sb-state |cut -d" " -f2)
    if [ "$secure_boot" == "enabled" ]
    then
        command_divider "Secure boot is enabled.  Cannot run sudo lctl dk dump_kernel"
    else
        command_divider "sudo lctl dk dump_kernel"
        sudo lctl dk dump_kernel |tee -a "$log" > /dev/null
        sudo chmod 666 dump_kernel
        command_divider "find /var/crash -ls"
        find /var/crash -ls |tee var_crash >> "$log"
    fi
    local_lustre_mounts=$(lfs getname |awk '{print $2}')
    if [ "$local_lustre_mounts" ]
    then
        for read_ahead_kb in /sys/devices/virtual/bdi/lustrefs-*/read_ahead_kb
        do
            command_divider "cat $read_ahead_kb"
            echo -n "$read_ahead_kb: " >> read_ahead_kb
            tee -a read_ahead_kb < "$read_ahead_kb" >> "$log"
        done
        for local_lustre_mount in $local_lustre_mounts
        do
            command_divider "lfs quota -hv $local_lustre_mount"
            lfs quota -hv "$local_lustre_mount" |tee -a lfs_quota >> "$log"
        done
    else
        command_divider "Lustre/amlfs is not mounted by client!"
    fi

    if [ "$read_ahead_kb" ]
    then
        echo "Further analysis required if read_ahead_kb is > 0" >> "$log"
    else
        command_divider "client does not contain a value for lustrefs read_ahead_kb.  All good."
    fi
    if [ "$run_hsm_state" ]
    then
        display_hsm_state # call subroutine to display hsm_state of all files.  May be time consuming.
    fi

    sudo chmod 666 ./*
    cd ..
    gsi_compressed=$(echo "$clientgsidir".tgz |sed 's/:/-/g')
    tar cvfz "$gsi_compressed" "$clientgsidir"/ >/dev/null
}

check_prerequisites() {
    prerequisites_met=1
    if [[ ! -d $logdir ]] || [[ ! -w $logdir ]]
    then
        >&2 echo "ERROR: log directory $logdir must exist and be writable"
        prerequisites_met=0
    fi
    sudo_works=$(sudo -n uptime 2>&1 | grep -c "load")
    if [ "$sudo_works" == 0 ]
    then
        >&2 echo "ERROR: sudo access is required to run gsi-client.sh"
        prerequisites_met=0
    fi
    lfs_exists=$(which lfs)
    lctl_exists=$(which lctl)
    lnetctl_exists=$(which lnetctl)
    if [ "$lfs_exists" ] || [ "$lctl_exists" ] || [ "$lnetctl_exists" ]
    then
        echo "Yes, Lustre client!"
    else
        echo "not a lustre client"
        prerequisites_met=0
    fi

    if [ $prerequisites_met != 1 ]
    then
        exit
    fi
}

find_vm_sku() {
    if [[ -f /run/cloud-init/instance-data.json ]]
    then
        vm_size=$(grep -E vmSize /run/cloud-init/instance-data.json |cut -d: -f2 | awk -F',' '{print $1}' |cut -d: -f2 |sed 's/\"//g' | sed 's/^ //')
        vm_sku=$(grep -E -m 1 sku /run/cloud-init/instance-data.json  |cut -d: -f2 | awk -F',' '{print $1}' |cut -d: -f2 |sed 's/\"//g' | sed 's/^ //')
        command_divider "extracting vm vmSize and sku from file /run/cloud-init/instance-data.json."
        echo "$vm_sku" |tee vm_sku >> "$log"
        echo "$vm_size" |tee vm_size >> "$log"
        command_divider "cat /run/cloud-init/instance-data.json"
        tee instance-data.json < /run/cloud-init/instance-data.json > /dev/null
    else
        command_divider "Skipping vmSize and sku as file /run/cloud-init/instance-data.json is NOT found."
    fi
}

command_divider() {
    echo "$(date +"%FT%T"): "
    echo "$(date +"%FT%T"): ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "$(date +"%FT%T"): command: ${*}"
    echo "$(date +"%FT%T"): "
} >> "$log"

get_logs() {
    if [ -f /var/log/syslog ]
    then
        cd /var/log || exit
        command_divider "cd /var/log; tail -30 syslog"
        sudo tail -30 syslog |tee >> "$log"
        command_divider "cd /var/log; tar cvfz $logdir/$clientgsidir/syslog.tgz syslog*"
        sudo tar cvfz "$logdir"/"$clientgsidir"/syslog.tgz syslog* |tee -a "$log" > /dev/null
        cd "$logdir"/"$clientgsidir" || exit
    fi
    if [ -f /var/log/messages ]
    then
        cd /var/log || exit
        command_divider "cd /var/log; sudo tail -30 messages"
        sudo tail -30 messages |tee >> "$log"
        command_divider "cd /var/log; sudo tar cvfz $logdir/$clientgsidir/messages.tgz messages*"
        sudo tar cvfz "$logdir"/"$clientgsidir"/messages.tgz messages* |tee -a "$log" > /dev/null
        cd "$logdir"/"$clientgsidir" || exit
    fi
}

display_hsm_state() {
    if [ "$local_lustre_mounts" ]
    then
        for local_lustre_mount in $local_lustre_mounts
        do
            command_divider "find $local_lustre_mount -type f -print0 |xargs -0 -n 1 lfs  hsm_state"
            hsm_state_file=$(echo "hsm_state$local_lustre_mount" |sed 's/\//_/g')
            echo "$local_lustre_mount" |tee "$hsm_state_file" >> "$log"
            find "$local_lustre_mount" -type f -print0 |xargs -0 -n 1 lfs hsm_state >> "$hsm_state_file"
            number_of_files=$(wc -l "$hsm_state_file")
            echo "Number of files: $number_of_files" |tee -a "$hsm_state_file" >> "$log"
        done
    else
        command_divider "Cannot find local lustre mount point.  Unable to display hsm_state."
    fi
}
main "$@"
exit
