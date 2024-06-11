#!/bin/bash
# SPDX-License-Identifier: MIT


function assemble_distcc_hosts {
  # Assembles the DISTCC_HOSTS environment variable, to be passed to distcc(1),
  # based on the local job slot count ($1), the local preprocessor count ($2),
  # and the worker specifications in the remaining variadic parameter ($@).
  #
  # Returns a single string that should be the environment variable.

  local -a distcc_hosts=()

  local -ri localhost_compilers="$1"
  local -ri localhost_preprocessors="$2"
  shift 2

  if [ "$localhost_compilers" -gt 0 ]; then
    distcc_hosts+=("localhost/$localhost_compilers"
      "--localslots=$localhost_compilers")
  fi
  if [ "$localhost_preprocessors" -gt 0 ]; then
    distcc_hosts+=("--localslots_cpp=$localhost_preprocessors")
  fi

  for worker_specification in "$@"; do
    local -a worker_specification_fields
    IFS='/' read -ra worker_specification_fields <<< "$worker_specification"

    local hostname="${worker_specification_fields[1]}"
    local -i job_port="${worker_specification_fields[2]}"
    local -i thread_count="${worker_specification_fields[4]}"

    distcc_hosts+=("$hostname:$job_port/$thread_count,lzo")
  done

  echo "${distcc_hosts[@]}"
}


function execute_user_command_under_distcc {
  # Actually executes the user-specified command with passing the job count $1
  # in a command-line parameter and running with $2 set as the 'DISTCC_HOSTS'
  # environment variable. The rest of the variadic input parameters ($@) specify
  # the command to execute.

  local -ri build_system_jobs="$1"
  local -r distcc_hosts_str="$2"
  shift 2

  debug "Executing command: $*"

  # Clean up the environment of the executed main command by unsetting variables
  # that were used as configuration inputs to the driver script.
  #
  # shellcheck disable=2046
  env \
    $(concatenate_config_unset_directives) \
    --unset="DCCSH_DEBUG" \
    --unset="DCCSH_TEMP" \
    CCACHE_PREFIX="distcc" \
    DISTCC_HOSTS="$distcc_hosts_str" \
      "$@" \
        -j "$build_system_jobs" \
    ;
}
