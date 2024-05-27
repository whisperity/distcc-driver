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


function _debug {
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
  export _DCCSH_ECHO_N=0
  if [ "$1" == "-n" ]; then
    export _DCCSH_ECHO_N=1
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

  _debug "DISTCC_AUTO_HOSTS:    $DISTCC_AUTO_HOSTS"
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
  # in the following format: an array of "PROTOCOL/HOST/PORT/STAT_PORT"
  # (**WITH** the quotes!).
  local DCCSH_HOSTS=()

  for hostspec in $1; do
    local original_hostspec="$hostspec"
    _debug "Parsing DISTCC_AUTO_HOSTS entry: \"$hostspec\" ..."

    local hostname
    local protocol
    protocol="$(echo "$hostspec" | grep -Eo "^.*?://" | sed 's/:\/\/$//')"
    hostspec="${hostspec/"$protocol://"/}"

    case "$protocol" in
      "tcp"|*)
        protocol="tcp"
        _debug "  - TCP"

        local match_ipv4
        local match_ipv6
        match_ipv4="$(echo "$hostspec" | grep -Po "$IPv4_REGEX")"
        match_ipv6="$(echo "$hostspec" | grep -Eo "$IPv6_REGEX")"
        if [ -n "$match_ipv4" ]; then
          hostname="$match_ipv4"
          hostspec="${hostspec/"$hostname"/}"
          _debug "  - Host (IPv4): $hostname"
        elif [ -n "$match_ipv6" ]; then
          hostname="$match_ipv6"
          hostspec="${hostspec/\["$hostname"\]/}"
          _debug "  - Host (IPv6): $hostname"
        else
          hostname="$(echo "$hostspec" | grep -Eo '^([^:]*)')"
          hostspec="${hostspec/"$hostname"/}"
          _debug "  - Host: $hostname"
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
      _debug "  - Port: $job_port"
    fi
    match_port="$(echo "$hostspec" | grep -Eo '^:[0-9]{1,5}' | sed 's/^://')"
    if [ -n "$match_port" ]; then
      # If the match-port matched **twice**, the second match MUST be the
      # "stats port", as per the grammar definition for DISTCC_AUTO_HOSTS.
      stat_port="$match_port"
      hostspec="${hostspec/":$stat_port"/}"
      _debug "  - Stat: $stat_port"
    fi

    # After parsing, the hostspec should have emptied.
    if [ -n "$hostspec" ]; then
      echo "WARNING: Parsing of malformed DISTCC_AUTO_HOSTS entry" \
        "\"$original_hostspec\" did not conclude cleanly and \"$hostspec\"" \
        "was ignored!" >&2
    fi

    local result="\"$protocol/$hostname/$job_port/$stat_port\""
    DCCSH_HOSTS+=("$result")
  done

  # Return value.
  echo "${DCCSH_HOSTS[@]}"
}


function distcc_driver {
  # The main entry point to the implementation of the job deployment client.
  _debug "Invoking command line is: $*"
  print_configuration

  if [ -z "$DISTCC_AUTO_HOSTS" ]; then
    echo "ERROR: 'distcc_driver' called without setting 'DISTCC_AUTO_HOSTS'!" >&2
    exit 2
  fi
  local DCCSH_HOSTS=("$(parse_distcc_auto_hosts "${DISTCC_AUTO_HOSTS:=}")")

  "$@"
}
