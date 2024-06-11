#!/bin/bash
# SPDX-License-Identifier: MIT


function create_administrative_tempdir {
  # Create a temporary directory for communication side-effects of helper
  # functions that are executed in a subshell by command substitution, or in the
  # background.

  if [ -z "$DCCSH_TEMP" ]; then
    export DCCSH_TEMP
    DCCSH_TEMP="$(mktemp \
      --directory \
      --tmpdir="$XDG_RUNTIME_DIR" \
      "distcc-driver.XXXXXXXXXX" \
      )"
  fi

  if [ ! -d "$DCCSH_TEMP" ]; then
    mkdir "$DCCSH_TEMP"
    chmod 1770 "$DCCSH_TEMP"

    if [ ! -d "$DCCSH_TEMP" ]; then
      log "FATAL" "Failed to actually create a necessary temporary directory:" \
        "\"$DCCSH_TEMP\"!"
      return 96
    fi
  fi
  debug "Using administrative temporary directory: $DCCSH_TEMP"

  trap "cleanup" EXIT
}


function cleanup {
  # Cleans up some potential side effects created by the driver's execution,
  # such as temporary directories, tunnels, etc.

  # Do not allow further signals during the clean-up process.
  trap "" HUP INT TERM

  local -a registered_cleanups=()
  mapfile -t registered_cleanups < \
    <(grep -v '^#\|^$' "$DCCSH_TEMP/cleanup" 2>/dev/null \
      | head -c -1)

  for func in "${registered_cleanups[@]}"; do
    "$func"
  done

  if [ -z "$DCCSH_DEBUG" ]; then
    rm -rf "$DCCSH_TEMP"
  else
    debug "Skip removing administrative temporary directory: $DCCSH_TEMP"
  fi

  unset DCCSH_TEMP
}


function register_cleanup {
  # Adds the specified function's **NAME** in $1 to the list of cleanup
  # functions executed when the script's execution is over, if it is not already
  # registered.

  local -r fn="$1"

  local -a registered_cleanups=()
  mapfile -t registered_cleanups < \
    <(grep -v '^#\|^$' "$DCCSH_TEMP/cleanup" 2>/dev/null \
      | head -c -1)

  for func in "${registered_cleanups[@]}"; do
    if [ "$func" == "$fn" ]; then
      return
    fi
  done

  echo "$fn" >> "$DCCSH_TEMP/cleanup"
}
