#!/bin/bash
# SPDX-License-Identifier: MIT

function load_host_tcp {
  # Checks that the tools needed by the TCP library are available, and sources
  # additional scripts that are part of the library.
  #
  # Returns 1 (fail) if the system failed to load, and 0 (success) otherwise.

  if \
      ! check_command grep "ERROR" || \
      ! check_command sed "ERROR" || \
      false; then
    log "ERROR" "\"lib/host/tcp\" failed to load due to missing utilities."
    return 1
  fi

  return 0
}


function parse_hostspec_tcp {
  # Parses a hostspec string, which is according to the TCP_HOST grammar.
  #
  # Returns the single '/'-separated split specification fields:
  # "PROTOCOL/HOST/PORT/STAT_PORT"

  local hostspec="$1"
  local -r original_hostspec="$hostspec"

  local hostname
  hostname="$(extract_hostname_from_hostspec "$hostspec")"
  hostspec="${hostspec/"$hostname"/}"

  if [ "$hostname" == "localhost" ]; then
    # "localhost", as a **HOSTNAME**, has a special meaning for DistCC ("do not
    # distribute").
    # Thus, it must be replaced with the actual loopback address, so the client
    # connects over the socket instead.
    hostname="$(get_loopback_address)"
  fi

  local -i job_port
  job_port="$(distcc_default_port)"
  local -i stat_port
  stat_port="$(distcc_default_stats_port)"

  local match_port
  match_port="$(echo "$hostspec" | grep -Eo '^:[0-9]{1,5}' | sed 's/^://')"
  if [ -n "$match_port" ]; then
    # If the match-port matched **once**, it MUST be the "job port", as per
    # the grammar definition for TCP_HOST.
    job_port="$match_port"
    hostspec="${hostspec/":$job_port"/}"
    debug "  - Port: $job_port"
  fi
  match_port="$(echo "$hostspec" | grep -Eo '^:[0-9]{1,5}' | sed 's/^://')"
  if [ -n "$match_port" ]; then
    # If the match-port matched **twice**, the second match MUST be the
    # "stats port", as per the grammar definition for TCP_HOST.
    stat_port="$match_port"
    hostspec="${hostspec/":$stat_port"/}"
    debug "  - Stat: $stat_port"
  fi

  # After parsing, the hostspec should have emptied.
  if [ -n "$hostspec" ]; then
    log "WARNING" "Parsing of malformed TCP host specification" \
      "\"$original_hostspec\" did not conclude cleanly, and \"$hostspec\"" \
      "was ignored!"
  fi

  array '/' "tcp" "$hostname" "$job_port" "$stat_port"
}


function transform_hostspec_tcp {
  # Returns the hostspec $1 unaltered.
  # This function is defined because the transformer logic is indiscriminatively
  # called for each protocol.

  echo "$1"
}
