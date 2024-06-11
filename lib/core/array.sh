#!/bin/bash
# SPDX-License-Identifier: MIT

function array {
  # Joins the array elements specified $2 and onwards by the delimiter character
  # specified in $1.
  # Returns the joint array a single string.
  #
  # Adapted from http://stackoverflow.com/a/17841619.

  local -r delimiter=${1-}
  local -r first=${2-}

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
