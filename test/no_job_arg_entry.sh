#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Exposes a fake top-level entry point "executable" which stripts the "-j N"
# argument automatically added by the driver script and executes any command
# that way.


function main {
  local args=()

  while [ $# -gt 0 ]; do
    local arg="$1"
    shift 1

    if [ "$arg" == "-j" ]; then
      shift 1
      continue
    fi

    args+=("$arg")
  done

  local cmd="${args[*]}"
  echo "Executing: $cmd" >&2
  exec $cmd
}


main "$@"
