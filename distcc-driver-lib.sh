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
#
# SUMMARY
#
#   Underlying implementation of business logic for the DistCC remote auto-job
#   script.
#
#
# CONFIGURATION ENVIRONMENT VARIABLES
#
#   For most user-facing configuration variables, please see the documentation
#   of 'distcc.sh' instead.
#
#     DCCSH_DEBUG               If defined to a non-empty string, additional
#                               debugging and tracing information is printed.
#
#
# AUTHOR
#
#    @Whisperity <whisperity-packages@protonmail.com>
#
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


# Set up configuration variables that are holding the default value for the
# user-configurable options.
_DCCSH_DEFAULT_DISTCC_PORT=3632
_DCCSH_DEFAULT_STATS_PORT=3633
_DCCSH_DEFAULT_DISTCC_AUTO_COMPILER_MEMORY=1024
_DCCSH_DEFAULT_DISTCC_AUTO_EARLY_LOCAL_JOBS=0


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
_check_command free
_check_command grep
_check_command sed

if [ "$_DCCSH_HAS_MISSING_TOOLS" -ne 0 ]; then
  exit 2
fi


function debug {
  # Prints all the arguments $@ (with the first argument $1 being "-n" for
  # skipping the newline printing), similarly to the built-in 'echo', with
  # an appropriate function prefix indicating where the debug printout was
  # called from.

  if [ -z "$DCCSH_DEBUG" ]; then
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


function array {
  # Joins the array elements specified $2 and onwards by the delimiter character
  # specified in $1.
  # Returns the joint array a single string.
  #
  # Adapted from http://stackoverflow.com/a/17841619.

  local delimiter=${1-}
  local first=${2-}

  if ! shift 2; then
    return 0
  fi

  if [[ "$first" == *"$delimiter"* || "$*" == *"$delimiter"* ]]; then
    echo "array: ERROR: Requested delimiter '""$delimiter""' found in" \
      "input elements: $first $*" >&2
    return 1
  fi

  printf "%s" "$first" "${@/#/$delimiter}"
  return 0
}


function print_configuration {
  # Print the input configuration options that are relevant for debugging.
  if [ -z "$DCCSH_DEBUG" ]; then
    return
  fi

  debug "DISTCC_AUTO_HOSTS:            $DISTCC_AUTO_HOSTS"
  debug "DISTCC_AUTO_COMPILER_MEMORY:  $DISTCC_AUTO_COMPILER_MEMORY"
  debug "DISTCC_AUTO_EARLY_LOCAL_JOBS: $DISTCC_AUTO_EARLY_LOCAL_JOBS"
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

    local job_port="$_DCCSH_DEFAULT_DISTCC_PORT"
    local stat_port="$_DCCSH_DEFAULT_STATS_PORT"
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
        "\"$original_hostspec\" did not conclude cleanly, and \"$hostspec\"" \
        "was ignored!" >&2
    fi

    DCCSH_HOSTS+=("$(array '/' \
      "$protocol" "$hostname" "$job_port" "$stat_port")")
  done

  # Return value.
  echo "${DCCSH_HOSTS[@]}"
}


function fetch_worker_capacity {
  # Downloads and parses **one** DistCC host's ($1) "statistics" output to
  # extract the server's capacity and statistical details from it.
  # Returns the worker capacity information: "THREAD_COUNT/LOAD_AVG/FREE_MEM".

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
  array '/' "$dcc_max_kids" "$dcc_load_average" "$dcc_free_mem"
}

function fetch_worker_capacities {
  # Download and assemble the worker capacities for all the hosts specified in
  # $1.
  # Returns the worker host specifications concatenated with the capacity
  # information for each array element.

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


function scale_worker_job_counts {
  # Calculates how many jobs should be dispatched (at maximum) to each already
  # queried worker in $2, based on the workers' capacities and the expected
  # per-job memory use value passed under $1.

  local requested_per_job_mem="$1"
  if [ "$requested_per_job_mem" -le 0 ]; then
    # Return value.
    echo "$2"
    return
  fi

  local DCCSH_WORKERS=()

  for worker_specification in $2; do
    local worker_specification_fields
    IFS='/' read -ra worker_specification_fields <<<"$worker_specification"

    local available_memory="${worker_specification_fields[6]}"
    if [ "$available_memory" == "-1" ]; then
      # If no memory information is available about the worker, assume that it
      # will be able to handle the number of jobs it exposes that it could
      # handle, and do not do any scaling.
      DCCSH_WORKERS+=("$worker_specification")
      continue
    fi

    local thread_count="${worker_specification_fields[4]}"
    local scaled_thread_count="$(( available_memory / requested_per_job_mem ))"
    if [ "$scaled_thread_count" -eq 0 ]; then
      debug "Skipping worker (available memory: $available_memory MiB):" \
        "$protocol://$hostname:$job_port"
      continue
    elif [ "$scaled_thread_count" -lt "$thread_count" ]; then
      local protocol="${worker_specification_fields[0]}"
      local hostname="${worker_specification_fields[1]}"
      local job_port="${worker_specification_fields[2]}"
      debug "Scaling down worker \"$protocol://$hostname:$job_port\"" \
        "(available memory: $available_memory MiB):" \
        "$thread_count -> $scaled_thread_count"

      worker_specification_fields[4]="$scaled_thread_count"
    fi

    DCCSH_WORKERS+=("$(array '/' "${worker_specification_fields[@]}")")
  done

  # Return value.
  echo "${DCCSH_WORKERS[@]}"
}

function scale_local_job_count {
  # Calculates how many jobs should be run (at maximum) immediately on the local
  # machine based on the number of **requested** local jobs in $1 and the
  # per-job expected memory consumption in $2, and the amount of available
  # memory in $3.
  # Returns the number of jobs to schedule, which might be "0" if no local work
  # should or could be done.

  local local_jobs="$1"
  local requested_per_job_mem="$2"
  local available_memory="$3"
  if [ "$local_jobs" -eq 0 ] \
      || [ "$requested_per_job_mem" -le 0 ] \
      || [ "$available_memory" -le 0 ]; then
    # Return value.
    echo "$local_jobs"
    return
  fi

  local scaled_thread_count="$(( available_memory / requested_per_job_mem ))"
  if [ "$scaled_thread_count" -eq 0 ]; then
    debug "Skipping local jobs (not enough RAM)"
    local_jobs="0"
  elif [ "$scaled_thread_count" -lt "$local_jobs" ]; then
    debug "Scaling local jobs (not enough RAM):" \
      "$local_jobs -> $scaled_thread_count"
    local_jobs="$scaled_thread_count"
  fi

  # Return value.
  echo "$local_jobs"
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

  local requested_per_job_mem
  if [ "$DISTCC_AUTO_COMPILER_MEMORY" == "0" ]; then
    debug "DISTCC_AUTO_COMPILER_MEMORY == \"0\": Skip scaling workers"
  else
    requested_per_job_mem="${DISTCC_AUTO_COMPILER_MEMORY:-"$_DCCSH_DEFAULT_DISTCC_AUTO_COMPILER_MEMORY"}"
    DCCSH_WORKERS=("$(scale_worker_job_counts \
      "$requested_per_job_mem" \
      "${DCCSH_WORKERS[@]}")")
  fi

  debug "Effective remote specification:"
  # shellcheck disable=SC2068
  for worker_specification in ${DCCSH_WORKERS[@]}; do
    debug "  - $worker_specification"
  done


  local requested_local_jobs
  if [ "${#DCCSH_WORKERS}" -ne 0 ]; then
    requested_local_jobs="${DISTCC_AUTO_EARLY_LOCAL_JOBS:-"$_DCCSH_DEFAULT_DISTCC_AUTO_EARLY_LOCAL_JOBS"}"
    debug "Requesting $requested_local_jobs local jobs ..." \
      "(from DISTCC_AUTO_EARLY_LOCAL_JOBS)"
  else
    # FIXME: (Re-)implement falling back to $(nproc) jobs in a configurable way
    # if no remotes exist.
    requested_local_jobs=$(nproc)
  fi

  if [ "$requested_local_jobs" -eq 0 ]; then
    debug "Local job count == 0: Skip scaling local"
  else
    local available_local_memory
    available_local_memory="$(free -m | grep "^Mem:" | awk '{ print $7 }')"
    debug "  - \"Available\" memory: $available_local_memory MiB"

    requested_local_jobs="$(scale_local_job_count \
      "$requested_local_jobs" \
      "$requested_per_job_mem" \
      "$available_local_memory")"
    debug "  - Local job #: $requested_local_jobs"
  fi


  if [ "${#DCCSH_WORKERS}" -eq 0 ] && [ "$requested_local_jobs" -eq 0 ]; then
    echo "ERROR: Refusing to build!" >&2
    echo "There are NO remote workers available, and there is not enough" \
      "memory for local compilation." >&2
    exit 3
  fi


  # Clean up the environment of the executed main command by unsetting variables
  # that were used as configuration inputs to the driver script.
  unset_internal_env_vars
  env \
    --unset="DISTCC_AUTO_HOSTS" \
    --unset="DISTCC_AUTO_COMPILER_MEMORY" \
    --unset="DISTCC_AUTO_EARLY_LOCAL_JOBS" \
    "$@"
}
