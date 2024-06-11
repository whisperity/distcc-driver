#!/bin/bash
# SPDX-License-Identifier: MIT


function log {
  # Emits a log message to the standard error.
  local -r severity="$1"
  shift 1

  echo "distcc-driver - $severity: $*" >&2
}


function debug {
  # Prints all the arguments $@ (with the first argument $1 being "-n" for
  # skipping the newline printing), similarly to the built-in 'echo', with
  # an appropriate function prefix indicating where the debug printout was
  # called from.

  if [ -z "$DCCSH_DEBUG" ]; then
    return
  fi

  local -ri prev_debug_skipped_newline="${_DCCSH_ECHO_N:=0}"
  local -r caller_func="${FUNCNAME[1]}"
  # local -r file="${BASH_SOURCE[1]}"
  local -ri line="${BASH_LINENO[0]}"
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


function check_command {
  # Checkes whether the system tool $1 is installed and available for calling
  # in a shell.
  # Logs a message with severity $2 if not available.
  #
  # Returns 1 (fail) if the tool is not available, and 0 (success) otherwise.

  local severity="$2"
  if [ -z "$severity" ]; then
    severity="FATAL"
  fi

  local -r program="$1"
  if ! command -v "$program" >/dev/null; then
    log "$severity" "System utility '$program' is not installed!"
    return 1
  fi

  return 0
}

function load_core {
  # Checks that the tools needed by the core library are available, and sources
  # additional scripts that are part of the library.
  #
  # Returns 1 (fail) if the system failed to load, and 0 (success) otherwise.

  if \
      ! check_command awk || \
      ! check_command chmod || \
      ! check_command curl || \
      ! check_command cut || \
      ! check_command env || \
      ! check_command free || \
      ! check_command grep || \
      ! check_command head || \
      ! check_command ip || \
      ! check_command mkdir || \
      ! check_command mktemp || \
      ! check_command nproc || \
      ! check_command rm || \
      ! check_command sed || \
      ! check_command sort || \
      ! check_command tr || \
      false; then
    log "FATAL" "\"lib/core\" failed to load due to missing utilities."
    return 1
  fi

  source "$DCCSH_SCRIPT_PATH/lib/core/array.sh"
  source "$DCCSH_SCRIPT_PATH/lib/core/config.sh"
  source "$DCCSH_SCRIPT_PATH/lib/core/distcc.sh"
  source "$DCCSH_SCRIPT_PATH/lib/core/host.sh"
  source "$DCCSH_SCRIPT_PATH/lib/core/hostname.sh"
  source "$DCCSH_SCRIPT_PATH/lib/core/local.sh"
  source "$DCCSH_SCRIPT_PATH/lib/core/remote.sh"
  source "$DCCSH_SCRIPT_PATH/lib/core/tempdir.sh"

  return 0
}


function assemble_worker_specifications {
  # Parses the first and only argument ($1) according to the 'DISTCC_AUTO_HOSTS'
  # config variable's "HOST SPECIFICATION" syntax, obtaining a list of remote
  # worker hosts.
  # For non-trivial (not pure TCP, e.g., SSH) hosts, protocol-specific
  # additional actions (e.g., for SSH, the connection to the remote machine and
  # setting up appropriate tunnels) take place.
  # Then queries the hosts to obtain the internal "WORKER SPECIFICATION", which
  # is the (potentially transformed, see above) "HOST SPECIFICATION" fields
  # extended with statistical and performance information.
  #
  # Returns the remote workers in a semicolon (';') separated array of
  # "PROTOCOL/HOST/PORT/STAT_PORT/THREAD_COUNT/LOAD_AVG/FREE_MEM"
  # entries.

  local -a parsed_hosts
  IFS=';' read -ra parsed_hosts <<< "$(parse_distcc_auto_hosts "$1")"
  IFS=';' read -ra parsed_hosts \
    <<< "$(unique_hosts "${parsed_hosts[@]}")"
  IFS=';' read -ra parsed_hosts \
    <<< "$(transform_non_trivial_hosts "${parsed_hosts[@]}")"

  local -a workers
  IFS=';' read -ra workers \
    <<< "$(fetch_worker_capacities "${parsed_hosts[@]}")"

  array ';' "${workers[@]}"
}
