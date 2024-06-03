#!/bin/bash
# SPDX-License-Identifier: MIT
#
################################################################################
### distcc-driver(1)      DistCC remote auto-job script     distcc-driver(1) ###
#
# NAME
#
#   distcc-driver-ssh
#
#
# SUMMARY
#
#   Handles connecting to and tunneling DistCC servers that are available behind
#   an SSH connection.
#
#
# AUTHOR
#
#    @Whisperity <whisperity-packages@protonmail.com>
#
################################################################################


_DCCSH_HAS_SSH_SUPPORT=1


function parse_ssh_hostspec {
  # Parses an AUTO_HOST_SPEC which is according to the SSH_HOST grammar.
  # Returns the single '/'-separated split specification fields:
  # "PROTOCOL/[USERNAME@]HOSTNAME[:PORT]/

  local hostspec="$1"
  local original_hostspec="$hostspec"

  local ssh_full_host
  ssh_full_host="$(echo "$hostspec" | grep -Eo '^([^/]*)')"

  local username
  local match_username
  match_username="$(echo "$ssh_full_host" | grep -Eo '^([^@]*)@' \
    | sed 's/@$//')"
  if [ -n "$match_username" ]; then
    username="$match_username"
    hostspec="${hostspec/"$username@"/}"
  fi

  local hostname
  hostname="$(echo "$hostspec" | grep -Eo '^([^/]*)')"
  hostname="$(get_hostname_from_hostspec "$hostname")"
  hostspec="${hostspec/"$hostname"/}"

  if [ -n "$username" ]; then
    debug "  - User: $username"
  fi

  local ssh_port
  local match_port
  match_port="$(echo "$hostspec" | grep -Eo '^:[0-9]{1,5}' | sed 's/^://')"
  if [ -n "$match_port" ]; then
    # If the match-port matched with ':' as the prefix, it MUST be the
    # "SSH port", as per the grammar definition for SSH_HOST.
    ssh_port="$match_port"
    hostspec="${hostspec/":$ssh_port"/}"
    debug "  - SSH port: $ssh_port"
  fi

  local job_port="$_DCCSH_DEFAULT_DISTCC_PORT"
  local stat_port="$_DCCSH_DEFAULT_STATS_PORT"
  match_port="$(echo "$hostspec" | grep -Eo '^/[0-9]{1,5}' | sed 's/^\///')"
  if [ -n "$match_port" ]; then
    # If the match-port matched **once** with '/' as the prefix, it MUST be the
    # "job port", as per the grammar definition for SSH_HOST.
    job_port="$match_port"
    hostspec="${hostspec/"/$job_port"/}"
    debug "  - Port: $job_port"
  fi
  match_port="$(echo "$hostspec" | grep -Eo '^/[0-9]{1,5}' | sed 's/^\///')"
  if [ -n "$match_port" ]; then
    # If the match-port matched **twice** with '/' as the prefix, the second
    # match MUST be the "stats port", as per the grammar definition for
    # SSH_HOST.
    stat_port="$match_port"
    hostspec="${hostspec/"/$stat_port"/}"
    debug "  - Stat: $stat_port"
  fi

  # After parsing, the hostspec should have emptied.
  if [ -n "$hostspec" ]; then
    log "WARNING" "Parsing of malformed DISTCC_AUTO_HOSTS entry" \
      "\"$original_hostspec\" did not conclude cleanly, and \"$hostspec\"" \
      "was ignored!"
  fi

  # Return value.
  array '/' "ssh" "$ssh_full_host" "$job_port" "$stat_port"
}


function act_upon_transform_ssh_hostspec {
  # TODO: We need to create a real SSH tunnel here and set up the local
  # forwarding of the remote ports.

  echo "act_upon_transform_ssh_hostspec: $*" >&2
}


function cleanup_ssh {
  echo "$0: cleanup_ssh" >&2
}
