#!/bin/bash
#
### distcc.sh(1)           DistCC remote auto-job script        distcc.sh(1) ###
#
# DESCRIPTION
#
#    This script depends on having ccache(1) installed and configured as your
#    C(++) building system. This generally means that the CC and CXX compilers
#    in your build process should come from /usr/lib/ccache.
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
