#!/bin/bash
# SPDX-License-Identifier: MIT


function parse_distcc_auto_hosts {
  # Parses the contents of the first argument ($1) according to the
  # 'DISTCC_AUTO_HOSTS' variable's specification syntax.
  # The output is the parsed hosts transformed down to an internal syntax,
  # in the following format: a semicolon (';') separated array of
  # "PROTOCOL/HOST/PORT/STAT_PORT" entries.
  #
  # Returns this formatted array.

  local -a hosts=()

  for hostspec in $1; do
    local original_hostspec="$hostspec"
    debug "Parsing DISTCC_AUTO_HOSTS entry: \"$hostspec\" ..."

    local protocol
    protocol="$(echo "$hostspec" | grep -Eo "^.*?://" | sed 's/:\/\/$//')"
    if [ -n "$protocol" ]; then
      protocol="${protocol,,}"
      hostspec="${hostspec/"$protocol://"/}"
    else
      protocol="tcp"
    fi
    debug "  - ${protocol^^}"

    if ! check_host_library "$protocol"; then
      local -r host_lib_complain_once_var="_dccsh_host_library_${protocol}_complained"
      if [ -z "${!host_lib_complain_once_var}" ]; then
        log "ERROR" "Skipping host entry \"$original_hostspec\" as its" \
          "protocol, \"$protocol\", is unknown or not supported in the" \
          "current environment." \
          "Skipping!"
        printf -v "$host_lib_complain_once_var" '%d' "1"
      fi

      continue
    fi

    local parsed_hostspec
    parsed_hostspec="$("parse_hostspec_${protocol}" "$hostspec")"

    hosts+=("$parsed_hostspec")
  done

  array ';' "${hosts[@]}"
}


function transform_non_trivial_hosts {
  # Transforms non-trivial host connections (e.g., SSH) into connections that
  # are actionable by DistCC, e.g., by opening an SSH tunnel, in the input
  # parsed host specification list passed as the variadic input parameter ($@).

  # Returns the remote workers in a semicolon (';') separated array of
  # "[ORIGINAL_HOST_SPECIFICATION=]TRANSFORMED_HOST_SPECIFICATION" entries,
  # where ORIGINAL_HOST_SPECIFICATION is the original
  # "PROTOCOL/HOST/PORT/STAT_PORT" as present in the input, and may not be
  # specified if no transformations were done; and
  # TRANSFORMED_HOST_SPECIFICATION is the same 4-tuple of fields but guaranteed
  # to be trivially actionable (aka. it is a pure TCP connection).

  local -a hosts=()

  for hostspec in "$@"; do
    local original_hostspec="$hostspec"
    local -a hostspec_fields
    IFS='/' read -ra hostspec_fields <<< "$hostspec"

    local protocol="${hostspec_fields[0]}"
    hostspec="$("transform_hostspec_${protocol}" "$hostspec")"
    if [ -z "$hostspec" ]; then
      log "ERROR" "Failed to transform and establish host:" \
        "$original_hostspec!"
      continue
    fi

    debug "Transformed \"$original_hostspec\" to \"$hostspec\""
    IFS='/' read -ra hostspec_fields <<< "$hostspec"
    protocol="${hostspec_fields[0]}"
    if ! check_host_library "$protocol"; then
      log "ERROR" "Failed to establish the post-transformation '$protocol'" \
        "host of \"$original_hostspec\"!"
    fi

    if [ "$original_hostspec" != "$hostspec" ]; then
      hosts+=("$original_hostspec=$hostspec")
    else
      hosts+=("$hostspec")
    fi
  done

  array ';' "${hosts[@]}"
}


function unique_hosts {
  # Removes duplicate entries from the input array of host specifications, as
  # passed through the variadic input parameter $@.
  # The operation is stable with regards to the original order, and does
  # **NOT** re-sort the resulting array.
  # Returns a semicolon (';') separated array of host specifications.

  echo -e "$(array '\n' "$@")" \
    | awk '!(line_seen[ $0 ]++)' \
    | head -c -1 \
    | tr '\n' ';'
}


function check_host_library {
  # Checks that the "host/" library corresponding to the protocol ($1) is
  # available and usable.
  # If the library can not be loaded, return 1 (fail), otherwise 0 (success).

  local -r protocol="${1,,}"
  local -r host_lib_check_var="_dccsh_host_library_${protocol}_checked"
  local -r host_lib_use_var="_dccsh_host_library_${protocol}_available"

  if [ -n "${!host_lib_check_var}" ]; then
    if [ "${!host_lib_check_var}" -eq 1 ]; then
      if [ "${!host_lib_use_var}" -eq 1 ]; then
        # Already loaded, known to be usable.
        return 0
      else
        # Already loaded, known to be unusable.
        return 1
      fi
    else
      # Already known to be non-loadable, thus, unusable.
      return 1
    fi
  fi

  # Not yet checked, try doing it it.
  printf -v "$host_lib_check_var" '%d' "1"

  load_host_"$protocol"
  local -ri lib_loaded=$?
  printf -v "$host_lib_use_var" '%d' "$(( ! lib_loaded ))"

  return $lib_loaded
}
