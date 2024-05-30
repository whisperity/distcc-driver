#!/bin/bash
# SPDX-License-Identifier: MIT
#
################################################################################
### distcc-driver(1)      DistCC remote auto-job script     distcc-driver(1) ###
#
# NAME
#
#   distcc-driver-lib.sh
#
# SYNOPSIS
#
#   Underlying implementation of business logic for the DistCC remote auto-job
#   script.
#
# CONFIGURATION ENVIRONMENT VARIABLES
#
#   For most user-facing configuration variables, please see 'distcc.sh'
#   instead.
#
#     DCCSH_DEBUG               If defined to a non-empty string, additional
#                               debugging and tracing information is printed.
#
# AUTHOR
#
#    @Whisperity <whisperity-packages@protonmail.com>
################################################################################


# This code should not be executed as a top-level script, because it only
# defines functions to be called by a wrapper script, see 'distcc.sh'.
case ${0##*/} in
  dash|-dash|bash|-bash|ksh|-ksh|sh|-sh)
    ;;
  bash_unit)
    # Allow `source` from the unit testing library.
    ;;
  *)
    echo "ERROR: The library script '${BASH_SOURCE[0]}' should not be" \
      "executed as a main script!" >&2
    exit 2
    ;;
esac


_DCCSH_HAS_MISSING_TOOLS=0
function _check_command {
  # This script depends on some usually available tools for helper calculations.
  # If these tools are not available, prevent loading the script.
  if ! command -v "$1" >/dev/null; then
    echo "ERROR: System utility '""$1""' is not installed!" \
      "This script can not run." >&2
    _DCCSH_HAS_MISSING_TOOLS=1
  fi
}

_check_command awk
_check_command curl
_check_command grep
_check_command sed

if [ $_DCCSH_HAS_MISSING_TOOLS -ne 0 ]; then
  exit 2
fi


function debug {
  # Prints all the arguments $@ (with the first argument $1 being "-n" for
  # skipping the newline printing), similarly to the built-in 'echo', with
  # an appropriate function prefix indicating where the debug printout was
  # called from.
  if [ -z "$DCSSH_DEBUG" ]; then
    return
  fi

  local prev_debug_skipped_newline="${_DCCSH_ECHO_N:=0}"
  local caller_func="${FUNCNAME[1]}"
  # local file="${BASH_SOURCE[1]}"
  local line="${BASH_LINENO[0]}"
  _DCCSH_ECHO_N=0
  if [ "$1" == "-n" ]; then
    _DCCSH_ECHO_N=1
    shift 1
  fi

  echo -n \
    "$( [ "$prev_debug_skipped_newline" -eq 0 ] && \
      echo "${caller_func}:${line}: " || echo)" \
    >&2
  echo -n "$@" >&2
  if [ "$_DCCSH_ECHO_N" -ne 1 ]; then
    echo >&2
  fi
}


function print_configuration {
  # Print the input configuration options that are relevant for debugging.
  if [ -z "$DCSSH_DEBUG" ]; then
    return
  fi

  debug "DISTCC_AUTO_HOSTS:    $DISTCC_AUTO_HOSTS"
}


function unset_config_env_vars {
  # Cleans up the environment of the executing shell by unsetting variables that
  # were used as configuration inputs to the driver script.

  unset DISTCC_AUTO_HOSTS
}

function unset_internal_env_vars {
  # Cleans up the environment of the executing shell by unsetting variables that
  # are otherwise globaly setl by this script for some cross-function purpose,
  # but not needed for the executing process.

  : # Noop.
}


# Via http://stackoverflow.com/a/36760050.
IPv4_REGEX='((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.){3}(25[0-5]|(2[0-4]|1\d|[1-9]|)\d)'

# Via http://stackoverflow.com/a/17871737.
# It is not a problem that it might match something more, because we just have
# to do a best guess whether the host is an IPv6 one.
IPv6_REGEX='(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))'

function parse_distcc_auto_hosts {
  # Parses the contents of the first argument $1 according to the
  # DISTCC_AUTO_HOSTS specification syntax.
  # The output is the parsed hosts transformed down to an internal syntax,
  # in the following format: an array of "PROTOCOL/HOST/PORT/STAT_PORT" entries.

  local DCCSH_HOSTS=()

  for hostspec in $1; do
    local original_hostspec="$hostspec"
    debug "Parsing DISTCC_AUTO_HOSTS entry: \"$hostspec\" ..."

    local hostname
    local protocol
    protocol="$(echo "$hostspec" | grep -Eo "^.*?://" | sed 's/:\/\/$//')"
    hostspec="${hostspec/"$protocol://"/}"

    case "$protocol" in
      "tcp"|*)
        protocol="tcp"
        debug "  - TCP"

        local match_ipv4
        local match_ipv6
        match_ipv4="$(echo "$hostspec" | grep -Po "$IPv4_REGEX")"
        match_ipv6="$(echo "$hostspec" | grep -Eo "$IPv6_REGEX")"
        if [ -n "$match_ipv4" ]; then
          hostname="$match_ipv4"
          hostspec="${hostspec/"$hostname"/}"
          debug "  - Host (IPv4): $hostname"
        elif [ -n "$match_ipv6" ]; then
          hostname="[$match_ipv6]"
          hostspec="${hostspec/"$hostname"/}"
          debug "  - Host (IPv6): $hostname"
        else
          hostname="$(echo "$hostspec" | grep -Eo '^([^:]*)')"
          hostspec="${hostspec/"$hostname"/}"
          debug "  - Host: $hostname"
        fi
        ;;
      # TODO: Implement handling local SSH tunnels for listening sockets.
    esac

    local job_port=3632
    local stat_port=3633
    local match_port
    match_port="$(echo "$hostspec" | grep -Eo '^:[0-9]{1,5}' | sed 's/^://')"
    if [ -n "$match_port" ]; then
      # If the match-port matched **once**, it MUST be the "job port", as per
      # the grammar definition for DISTCC_AUTO_HOSTS.
      job_port="$match_port"
      hostspec="${hostspec/":$job_port"/}"
      debug "  - Port: $job_port"
    fi
    match_port="$(echo "$hostspec" | grep -Eo '^:[0-9]{1,5}' | sed 's/^://')"
    if [ -n "$match_port" ]; then
      # If the match-port matched **twice**, the second match MUST be the
      # "stats port", as per the grammar definition for DISTCC_AUTO_HOSTS.
      stat_port="$match_port"
      hostspec="${hostspec/":$stat_port"/}"
      debug "  - Stat: $stat_port"
    fi

    # After parsing, the hostspec should have emptied.
    if [ -n "$hostspec" ]; then
      echo "WARNING: Parsing of malformed DISTCC_AUTO_HOSTS entry" \
        "\"$original_hostspec\" did not conclude cleanly and \"$hostspec\"" \
        "was ignored!" >&2
    fi

    local result="$protocol/$hostname/$job_port/$stat_port"
    DCCSH_HOSTS+=("$result")
  done

  # Return value.
  echo "${DCCSH_HOSTS[@]}"
}


function fetch_worker_capacity {
  # Downloads and parses **one** DistCC host's "statistics" output to extract
  # the server's capabilities and capacity from it.
  # Returns the worker capacity/capability information:
  # "THREAD_COUNT/LOAD_AVG/FREE_MEM".

  debug "Querying host capacity: $worker_connection ..."

  local worker_connection_fields
  IFS='/' read -ra worker_connection_fields <<<"$1"
  local hostname="${worker_connection_fields[1]}"
  local stat_port="${worker_connection_fields[3]}"

  local stat_response
  stat_response="$(curl "$hostname:$stat_port" \
    --connect-timeout "5" \
    --max-time "10" \
    --silent \
    --show-error)"
  # shellcheck disable=SC2181
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to query capacity of host" \
      "\"${worker_connection_fields[0]}://$hostname:${worker_connection_fields[2]}\"!" \
      "Likely the host is unavailable." \
      "See curl error message above for details!" \
      >&2
    return 1
  fi
  # debug -e "Raw DistCC --stats response:\n${stat_response}"

  local dcc_max_kids
  dcc_max_kids="$(echo "$stat_response" | grep "dcc_max_kids" \
    | cut -d ' ' -f 2)"
  debug "  - Threads: $dcc_max_kids"

  local dcc_loads
  mapfile -t dcc_loads -n 3 < \
    <(echo "$stat_response" | grep "dcc_load" | cut -d ' ' -f 2)
  debug "  - Load: ${dcc_loads[*]}"

  # (Unfortunately, Bash's $(( )) does *NOT* support floats. Zsh would.)
  local dcc_load_average
  dcc_load_average="$(echo "${dcc_loads[@]}" | \
    awk '{ print ($1 + $2 + $3) / 3 }')"
  debug "  - Load avg: $dcc_load_average"

  # FIXME: This is not implemented yet, only a proposal.
  # (See http://github.com/distcc/distcc/issues/521 for details.)
  local dcc_free_mem="-1"
  # debug "  - Memory: $dcc_free_mem"

  # Return value.
  echo "$dcc_max_kids/$dcc_load_average/$dcc_free_mem"
}

function fetch_worker_capacities {
  # Download and assemble the worker capacities for all the hosts specified as
  # the function's variadic arguments.

  local DCCSH_HOSTS_WITH_CAPS=()

  for worker_connection in $1; do
    local worker_capacity
    worker_capacity="$(fetch_worker_capacity "$worker_connection")"
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
      debug "Querying host capacity: $worker_connection FAILED!"
      continue
    fi

    DCCSH_HOSTS_WITH_CAPS+=("$worker_connection"/"$worker_capacity")
  done

  # Return value.
  echo "${DCCSH_HOSTS_WITH_CAPS[@]}"
}


function distcc_driver {
  # The main entry point to the implementation of the job deployment client.
  debug "Invoking command line is: $*"
  print_configuration

  if [ -z "$DISTCC_AUTO_HOSTS" ]; then
    echo "ERROR: 'distcc_driver' called without setting" \
      "'DISTCC_AUTO_HOSTS'!" >&2
    exit 2
  fi

  local DCCSH_HOSTS=("$(parse_distcc_auto_hosts "${DISTCC_AUTO_HOSTS:=}")")
  local DCCSH_WORKERS=("$(fetch_worker_capacities "${DCCSH_HOSTS[@]}")")

  debug "Workers: ${DCCSH_WORKERS[*]}"

  unset_internal_env_vars
  unset_config_env_vars

  "$@"
}
