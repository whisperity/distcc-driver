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


function log {
  # Emits a log message to the standard error.
  local severity="$1"
  shift 1

  echo "distcc-driver - $severity: $*" >&2
}


# This code should not be executed as a top-level script, because it only
# defines functions to be called by a wrapper script, see 'distcc.sh'.
case ${0##*/} in
  dash|-dash|bash|-bash|ksh|-ksh|sh|-sh)
    ;;
  bash_unit)
    # Allow `source` from the unit testing library.
    ;;
  *)
    log "FATAL" "The library script '${BASH_SOURCE[0]}' should not be" \
      "executed as a main script!"
    exit 96
    ;;
esac


_DCCSH_HAS_MISSING_TOOLS=0
function _check_command {
  # This script depends on some usually available tools for helper calculations.
  # If these tools are not available, prevent loading the script.

  if ! command -v "$1" >/dev/null; then
    log "FATAL" "System utility '""$1""' is not installed!"
    _DCCSH_HAS_MISSING_TOOLS=1
    return 1
  fi

  return 0
}

function check_commands {
  _check_command awk
  _check_command curl
  _check_command free
  _check_command grep
  _check_command nproc
  _check_command sed

  return "$_DCCSH_HAS_MISSING_TOOLS"
}


# Set up configuration variables that are holding the default value for the
# user-configurable options.
_DCCSH_DEFAULT_DISTCC_PORT=3632
_DCCSH_DEFAULT_STATS_PORT=3633
_DCCSH_DEFAULT_DISTCC_AUTO_COMPILER_MEMORY=1024
_DCCSH_DEFAULT_DISTCC_AUTO_EARLY_LOCAL_JOBS=0
_DCCSH_DEFAULT_DISTCC_AUTO_FALLBACK_LOCAL_JOBS="$(nproc)"
_DCCSH_DEFAULT_DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS="$(nproc)"


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
    echo "array() - ERROR: Requested delimiter '""$delimiter""' found in" \
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

  debug "DISTCC_AUTO_HOSTS:                       " \
    "$DISTCC_AUTO_HOSTS"

  debug "DISTCC_AUTO_COMPILER_MEMORY:             " \
    "$DISTCC_AUTO_COMPILER_MEMORY"
  if [ -z "$DISTCC_AUTO_COMPILER_MEMORY" ]; then
    debug "    (default):                           " \
      "$_DCCSH_DEFAULT_DISTCC_AUTO_COMPILER_MEMORY"
  fi

  debug "DISTCC_AUTO_EARLY_LOCAL_JOBS:            " \
    "$DISTCC_AUTO_EARLY_LOCAL_JOBS"
  if [ -z "$DISTCC_AUTO_EARLY_LOCAL_JOBS" ]; then
    debug "    (default):                           " \
      "$_DCCSH_DEFAULT_DISTCC_AUTO_EARLY_LOCAL_JOBS"
  fi

  debug "DISTCC_AUTO_FALLBACK_LOCAL_JOBS:         " \
    "$DISTCC_AUTO_FALLBACK_LOCAL_JOBS"
  if [ -z "$DISTCC_AUTO_FALLBACK_LOCAL_JOBS" ]; then
    debug "    (default):                           " \
      "$_DCCSH_DEFAULT_DISTCC_AUTO_FALLBACK_LOCAL_JOBS"
  fi

  debug "DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS:" \
    "$DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS"
  if [ -z "$DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS" ]; then
    debug "    (default):                           " \
      "$_DCCSH_DEFAULT_DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS"
  fi
}


# Via http://stackoverflow.com/a/36760050.
IPv4_REGEX='((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.){3}(25[0-5]|(2[0-4]|1\d|[1-9]|)\d)'

# Via http://stackoverflow.com/a/17871737.
# It is not a problem that it might match something more, because we just have
# to do a best guess whether the host is an IPv6 one.
IPv6_REGEX='(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))'

function parse_distcc_auto_hosts {
  # Parses the contents of the first argument ($1) according to the
  # DISTCC_AUTO_HOSTS specification syntax.
  # The output is the parsed hosts transformed down to an internal syntax,
  # in the following format: a semicolon (';') separated array of
  # "PROTOCOL/HOST/PORT/STAT_PORT" entries.

  local hosts=()

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
      log "WARNING" "Parsing of malformed DISTCC_AUTO_HOSTS entry" \
        "\"$original_hostspec\" did not conclude cleanly, and" \
        "\"$hostspec\" was ignored!"
    fi

    hosts+=("$(array '/' "$protocol" "$hostname" "$job_port" "$stat_port")")
  done

  # Return value.
  array ';' "${hosts[@]}"
}


function fetch_worker_capacity {
  # Downloads and parses **one** DistCC host's ($1) "statistics" output to
  # extract the server's capacity and statistical details from it.
  # Returns the worker capacity information: "THREAD_COUNT/LOAD_AVG/FREE_MEM".

  local hostspec="$1"
  debug "Querying host capacity: $hostspec ..."

  local worker_connection_fields
  IFS='/' read -ra worker_connection_fields <<< "$hostspec"
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
    log "ERROR" "Failed to query capacity of host" \
      "\"${worker_connection_fields[0]}://$hostname:$stat_port\"!" \
      "Likely the host is unavailable." \
      "See curl error message above for details!"
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
  # the variadic parameter list $@.
  # Returns the worker host specifications concatenated with the capacity
  # information for each array element, in the same semicolon (';') separated
  # format as with parse_distcc_auto_hosts.

  local workers=()

  for worker_connection in "$@"; do
    local worker_capacity
    worker_capacity="$(fetch_worker_capacity "$worker_connection")"
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
      debug "Querying host capacity: $worker_connection FAILED!"
      continue
    fi

    workers+=("$worker_connection"/"$worker_capacity")
  done

  # Return value.
  array ';' "${workers[@]}"
}


function get_raw_worker_specifications {
  # Parses the first and only argument ($1) according to the DISTCC_AUTO_HOSTS
  # config variable's "HOST SPECIFICATION" syntax, obtaining a list of remote
  # worker hosts.
  # Then queries the hosts to obtain the internal "WORKER SPECIFICATION", which
  # is the "HOST SPECIFICATION" fields extended with statistical and
  # performance information.
  # Returns the remote workers in a semicolon (';')-separated array of
  # "PROTOCOL/HOST/PORT/STAT_PORT/THREAD_COUNT/LOAD_AVG/FREE_MEM"
  # entries.

  local parsed_hosts
  IFS=';' read -ra parsed_hosts <<< "$(parse_distcc_auto_hosts "$1")"

  # Return value.
  fetch_worker_capacities "${parsed_hosts[@]}"
}


function scale_worker_job_counts {
  # Calculates how many jobs should be dispatched (at maximum) to each already
  # queried worker in $@ (the variadic input argument), based on the workers'
  # capacities and the expected per-job memory use value passed under $1.

  local requested_per_job_mem="$1"
  shift 1

  if [ "$requested_per_job_mem" -le 0 ]; then
    # Return value.
    echo "$@"
    return
  fi

  local workers=()

  for worker_specification in "$@"; do
    local worker_specification_fields
    IFS='/' read -ra worker_specification_fields <<< "$worker_specification"

    local available_memory="${worker_specification_fields[6]}"
    if [ "$available_memory" == "-1" ]; then
      # If no memory information is available about the worker, assume that it
      # will be able to handle the number of jobs it exposes that it could
      # handle, and do not do any scaling, as we have no way of executing the
      # scaling.
      workers+=("$worker_specification")
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

    workers+=("$(array '/' "${worker_specification_fields[@]}")")
  done

  # Return value.
  array ';' "${workers[@]}"
}

function sum_worker_job_counts {
  # Calculates the number of jobs to be dispatched to workers in total, based
  # on the worker specification provided under the variadic input $@.
  # Returns a single integer number.

  local remote_job_count=0

  for worker_specification in "$@"; do
    local worker_specification_fields
    IFS='/' read -ra worker_specification_fields <<< "$worker_specification"

    local worker_job_count="${worker_specification_fields[4]}"
    remote_job_count="$(( remote_job_count + worker_job_count ))"
  done

  # Return value.
  echo "$remote_job_count"
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


function assemble_distcc_hosts {
  # Assembles the DISTCC_HOSTS environment variable, to be passed to distcc(1),
  # based on the local job slot count ($1), the local preprocessor count ($2),
  # and the worker specifications in the remaining variadic parameter ($@).
  #
  # Returns a single string that should be the environment variable.

  local distcc_hosts=()

  local localhost_compilers="$1"
  local localhost_preprocessors="$2"
  shift 2

  if [ "$localhost_compilers" -gt 0 ]; then
    distcc_hosts+=("localhost/$localhost_compilers"
      "--localslots=$localhost_compilers")
  fi
  if [ "$localhost_preprocessors" -gt 0 ]; then
    distcc_hosts+=("--localslots_cpp=$localhost_preprocessors")
  fi

  for worker_specification in "$@"; do
    local worker_specification_fields
    IFS='/' read -ra worker_specification_fields <<< "$worker_specification"

    local hostname="${worker_specification_fields[1]}"
    local job_port="${worker_specification_fields[2]}"
    local thread_count="${worker_specification_fields[4]}"

    distcc_hosts+=("$hostname:$job_port/$thread_count,lzo")
  done

  # Return value.
  echo "${distcc_hosts[@]}"
}


function drive_distcc {
  # Actually executes the user-specified command with passing the job count $1
  # in a command-line parameter and running with $2 set as the 'DISTCC_HOSTS'
  # environment variable. The rest of the variadic input parameters ($@) specify
  # the command to execute.

  local build_system_jobs="$1"
  local distcc_hosts_str="$2"
  shift 2

  debug "Executing command: $*"
  # Clean up the environment of the executed main command by unsetting variables
  # that were used as configuration inputs to the driver script.
  env \
    --unset="DISTCC_AUTO_HOSTS" \
    --unset="DISTCC_AUTO_COMPILER_MEMORY" \
    --unset="DISTCC_AUTO_EARLY_LOCAL_JOBS" \
    --unset="DISTCC_AUTO_FALLBACK_LOCAL_JOBS" \
    --unset="DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS" \
    CCACHE_PREFIX="distcc" \
    DISTCC_HOSTS="$distcc_hosts_str" \
      "$@" \
        -j "$build_system_jobs"
}


function distcc_driver {
  # The main entry point to the implementation of the job deployment client.


  # Startup, configuration and environment checking.
  if ! check_commands; then
    exit 96
  fi

  if [ $# -eq 0 ]; then
    log "FATAL" "'distcc_driver' called without specifying a command to" \
      "execute!"
    exit 96
  fi

  if [ -z "$DISTCC_AUTO_HOSTS" ]; then
    log "FATAL" "'distcc_driver' called without setting 'DISTCC_AUTO_HOSTS'!"
    exit 96
  fi

  debug "Invoking command line is: $*"
  print_configuration


  # Parse user configuration of hosts and query worker capabilities.
  local workers
  IFS=';' read -ra workers \
    <<< "$(get_raw_worker_specifications "${DISTCC_AUTO_HOSTS:=}")"


  # Scale workers' known specification to available capacity, if needed.
  local requested_per_job_mem
  if [ "$DISTCC_AUTO_COMPILER_MEMORY" == "0" ]; then
    debug "DISTCC_AUTO_COMPILER_MEMORY == \"0\": Skip scaling workers"
  else
    requested_per_job_mem="${DISTCC_AUTO_COMPILER_MEMORY:-"$_DCCSH_DEFAULT_DISTCC_AUTO_COMPILER_MEMORY"}"
    IFS=';' read -ra workers \
      <<< "$(scale_worker_job_counts "$requested_per_job_mem" "${workers[@]}")"
  fi

  local num_remotes="${#workers[@]}"
  debug "Effective remote specification:"
  for worker_specification in "${workers[@]}"; do
    debug "  - $worker_specification"
  done


  # Decide the number of parallel jobs to run completely locally.
  local requested_local_jobs
  if [ "$num_remotes" -ne 0 ]; then
    requested_local_jobs="${DISTCC_AUTO_EARLY_LOCAL_JOBS:-"$_DCCSH_DEFAULT_DISTCC_AUTO_EARLY_LOCAL_JOBS"}"
    debug "Requesting $requested_local_jobs local jobs ..." \
      "(from DISTCC_AUTO_EARLY_LOCAL_JOBS)"
  else
    requested_local_jobs="${DISTCC_AUTO_FALLBACK_LOCAL_JOBS:-"$_DCCSH_DEFAULT_DISTCC_AUTO_FALLBACK_LOCAL_JOBS"}"
    debug "Requesting $requested_local_jobs local jobs ... " \
      "(from DISTCC_AUTO_FALLBACK_LOCAL_JOBS)"
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


  # Calculate the total width of parallelism to execute.
  if [ "$num_remotes" -eq 0 ] && [ "$requested_local_jobs" -eq 0 ]; then
    log "FATAL" "Refusing to build!"
    log "FATAL" "There are NO remote workers available, and local execution" \
      "was disabled either on request, or due to lack of available memory."
    exit 97
  fi

  local num_remote_jobs=0
  local preprocessor_saturation_jobs=0
  local total_job_count=0
  if [ "$num_remotes" -ne 0 ]; then
    num_remote_jobs="$(sum_worker_job_counts "${workers[@]}")"
    total_job_count="$(( num_remote_jobs + requested_local_jobs ))"
  else
    total_job_count="$requested_local_jobs"
  fi

  if [ "$total_job_count" -eq 0 ]; then
    log "FATAL (ASSERT) @ $LINENO" \
      "Total job count was $total_job_count but an earlier exit was not taken."
    exit 97
  fi

  local preprocessor_saturation_jobs="${DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS:-"$_DCCSH_DEFAULT_DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS"}"
  if [ "$preprocessor_saturation_jobs" -eq 0 ]; then
    debug "Preprocessor saturation job count == 0: Skip setting up"
  elif [ "$num_remotes" -eq 0 ]; then
    debug "No remote workers: skip preprocessor saturation jobs"
    preprocessor_saturation_jobs=0
  else
    total_job_count="$(( total_job_count + preprocessor_saturation_jobs ))"
  fi

  log "INFO" "Building '-j $total_job_count':"
  if [ "$requested_local_jobs" -gt 0 ]; then
    log "INFO" "  - $requested_local_jobs local compilations"
  fi
  if [ "$preprocessor_saturation_jobs" -gt 0 ]; then
    log "INFO" "  - $preprocessor_saturation_jobs preprocessor saturation"
  fi
  if [ "$num_remote_jobs" -gt 0 ]; then
    log "INFO" "  - $num_remote_jobs remote jobs (over $num_remotes hosts)"
  fi


  # Assemble environment and command to execute.
  local distcc_hosts
  distcc_hosts="$(assemble_distcc_hosts \
    "$requested_local_jobs" \
    "$preprocessor_saturation_jobs" \
    "${workers[@]}")"
  debug "Using DISTCC_HOSTS: ${distcc_hosts[*]}"


  # Fire away the user's requested command.
  drive_distcc "$total_job_count" "${distcc_hosts[@]}" "$@"
}
