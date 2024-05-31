#!/bin/bash
#
### distcc.sh(1)           DistCC remote auto-job script        distcc.sh(1) ###
#
# NAME
#
#    distcc.sh - DistCC remote auto-job script
#
# SYNOPSIS
#
#    source distcc.sh; distcc_build make my_target
#
# DESCRIPTION
#
#    This script depends on having ccache(1) installed and configured as your
#    C(++) building system. This generally means that the CC and CXX compilers
#    in your build process should come from /usr/lib/ccache.
#
#    A caveat built into this script is that the build machines should be
#    accessible as a local port. But this makes this script synergise well
#    with SSH tunnels.
#
# HOW TO SET UP SSH TUNNEL
#
#    In your SSH configuration file (conventionally ~/.ssh/config) use the
#    following template for a build worker machine:
#
#        AddKeysToAgent yes
#
#        Host mybuild1
#            HostName mybuild1.awesomedistcc.example.com
#            Port 22
#            User user
#            LocalForward 3632 localhost:3632    # NOTE: Important line!
#
#    Before executing the build, create an SSH tunnel. The first command loads
#    the connection in the foreground and asks for your SSH key's password
#    (if any), allowing the second command to run in the background.
#    (Otherwise, the asking-for-key-unlock would wait indefinitely.)
#
#        ssh mybuild1 'exit'; ssh -CNq mybuild1 &!
#
# AUTHOR
#
#    Whisperity (http://github.com/Whisperity)
################################################################################

# Returns true if $1 is listening on the local machine.
function check_tcpport_listen {
    _dccsh_debug -n "Check port $1..."

    ss -lnt | \
        tail -n +2 | \
        awk '{ print $4; }' | \
        awk -F":" '{ print $NF; }' | \
        grep "$1" \
        &>/dev/null
    local R=$?

    _dccsh_debug -n "    is listening? "
    if [ $R -eq 0 ]; then
        _dccsh_debug "YES"
    else
        _dccsh_debug "NO"
    fi

    return $R
}

# Build by concatenating $2 port with $3 jobs after $1 DISTCC_HOSTS string.
function _dccsh_concat_port {
    local PORT=$2
    local JOBS=$3

    if check_tcpport_listen "$PORT"; then
        local HOST_ENTRY="127.0.0.1:$PORT/$JOBS,lzo"
        _dccsh_debug "Concatenate \"$HOST_ENTRY\" after \"$1\""
        echo $1" $HOST_ENTRY"
        return 0
    else
        echo $1
        return 1
    fi
}

# Parses the DISTCC_PORTS environmental variable.
function _dccsh_parse_distcc_ports {
    DCCSH_HOSTS=""
    DCCSH_TOTAL_JOBS=0

    for port_and_jobs in $DISTCC_PORTS; do
        local PORT=$(echo $port_and_jobs | cut -d'/' -f 1)
        local JOBS=$(echo $port_and_jobs | cut -d'/' -f 2)
        _dccsh_debug "Adding: $PORT with $JOBS jobs..."

        DCCSH_HOSTS=$(_dccsh_concat_port "$DCCSH_HOSTS" $PORT $JOBS)
        if [ $? -eq 0 ]; then
            DCCSH_TOTAL_JOBS=$(($DCCSH_TOTAL_JOBS + $JOBS))
            _dccsh_debug "$PORT: responding, added, new total job count" \
                "is: $DCCSH_TOTAL_JOBS"
        else
            _dccsh_debug "$PORT: did not respond."
        fi
    done
}

# Adds building some TUs on the local machine to the DCCSH_ variables, based
# on environmental configuration.
function _dccsh_append_localhost {
    if [ $DCCSH_LOCAL_JOBS -gt 0 ]; then
        _dccsh_debug "Prioritising running $DCCSH_LOCAL_JOBS jobs locally!"
        DCCSH_HOSTS="localhost/${DCCSH_LOCAL_JOBS} $DCCSH_HOSTS"
        DCCSH_TOTAL_JOBS=$(($DCCSH_TOTAL_JOBS + $DCCSH_LOCAL_JOBS))
    else
        _dccsh_debug "Local job count was $DCCSH_LOCAL_JOBS, not appending" \
            "'localhost'"
    fi
}

function _dccsh_cleanup_vars {
    DCCSH_HOSTS=""
    DCCSH_LOCAL_JOBS=0
    DCCSH_MEM_PER_BUILD=0
}

# Actually executes the build with having DISTCC_HOSTS set and ccache set
# to run through distcc.
function _dccsh_run_distcc {
    local DISTCC_HOSTS_STR=$1
    shift 1

    _dccsh_debug "Executing with hosts: \"$DISTCC_HOSTS_STR\""
    _dccsh_debug "Executed command line: $@"
    DISTCC_HOSTS="$DISTCC_HOSTS_STR" CCACHE_PREFIX="distcc" $*
}

# Prepares running the build remotely. This is the entry point of the script.
function distcc_build {
    _dccsh_parse_distcc_ports

    _dccsh_append_localhost

    _dccsh_run_distcc "$DCCSH_HOSTS" $* -j "$DCCSH_TOTAL_JOBS"
    local R=$?

    _dccsh_cleanup_vars

    return $R
}
