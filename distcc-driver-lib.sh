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

  local PREV_DEBUG_SKIPPED_NEWLINE="${_DCCSH_ECHO_N:=0}"
  local CALLER_FUNC="${FUNCNAME[1]}"
  local FILE="${BASH_SOURCE[1]}"
  local LINE="${BASH_LINENO[0]}"
  export _DCCSH_ECHO_N=0
  if [ "x$1" == "x-n" ]; then
    export _DCCSH_ECHO_N=1
    shift 1
  fi

  echo -n \
    "$( [ "$PREV_DEBUG_SKIPPED_NEWLINE" -eq 0 ] && echo "${CALLER_FUNC}:${LINE}: " || echo)" \
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


function parse_distcc_auto_hosts {
  # Parses the contents of the first argument $1 according to the
  # DISTCC_AUTO_HOSTS specification syntax.
  local DCCSH_HOSTS=()

  for HOSTSPEC in $1; do
    # FIXME: Parse host as IPv4 and IPv6.
    # FIXME: Parse hostname TCP.
    # FIXME: Parse port numbers.

    # FIXME: [Architecture] Have some unit tests for these parsing routines.
    echo $HOSTSPEC >&2
  done

  echo "${DCCSH_HOSTS[@]}"
}


function distcc_driver {
  # The main entry point to the implementation of the job deployment client.
  _debug "Invoking command line is: $*"
  print_configuration
  local DCCSH_HOSTS=("$(parse_distcc_auto_hosts "$DISTCC_AUTO_HOSTS")")
  _debug "Hosts: ${DCCSH_HOSTS[@]}"

  $@
}
