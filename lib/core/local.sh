#!/bin/bash
# SPDX-License-Identifier: MIT


function get_local_job_count {
  # Returns the number of local jobs that should be used, based on whether there
  # are remote workers available ($1), the user's configuration in the relevant
  # environment variables, and the available amount of local memory.

  local -ri num_remotes="$1"
  local -ri requested_per_job_mem="$(distcc_auto_compiler_memory)"

  local -i requested_local_jobs

  if [ "$num_remotes" -ne 0 ]; then
    requested_local_jobs="$(distcc_auto_early_local_jobs)"
    debug "Requesting $requested_local_jobs local jobs ..." \
      "(from DISTCC_AUTO_EARLY_LOCAL_JOBS)"
  else
    requested_local_jobs="$(distcc_auto_fallback_local_jobs)"
    debug "Requesting $requested_local_jobs local jobs ... " \
      "(from DISTCC_AUTO_FALLBACK_LOCAL_JOBS)"
  fi

  if [ "$requested_local_jobs" -eq 0 ]; then
    debug "Local job count == 0: Skip scaling local"
  else
    local -i available_local_memory
    available_local_memory="$(free -m | grep "^Mem:" | awk '{ print $7 }')"
    debug "  - \"Available\" memory: $available_local_memory MiB"

    requested_local_jobs="$(scale_local_jobs \
      "$requested_local_jobs" \
      "$requested_per_job_mem" \
      "$available_local_memory")"
    debug "  - Local job #: $requested_local_jobs"
  fi

  echo "$requested_local_jobs"
}


function scale_local_jobs {
  # Calculates how many jobs should be run (at maximum) immediately on the local
  # machine based on the number of **requested** local jobs in $1 and the
  # per-job expected memory consumption in $2, and the amount of available
  # memory in $3.
  # Returns the number of jobs to schedule, which might be "0" if no local work
  # should or could be done.

  local -i local_jobs="$1"
  local -ri requested_per_job_mem="$2"
  local -ri available_memory="$3"
  if [ "$local_jobs" -eq 0 ] \
      || [ "$requested_per_job_mem" -le 0 ] \
      || [ "$available_memory" -le 0 ]; then
    echo "$local_jobs"
    return
  fi

  local -ri \
    scaled_thread_count="$(( available_memory / requested_per_job_mem ))"
  if [ "$scaled_thread_count" -eq 0 ]; then
    debug "Skipping local jobs (not enough RAM)"
    local_jobs="0"
  elif [ "$scaled_thread_count" -lt "$local_jobs" ]; then
    debug "Scaling local jobs (not enough RAM):" \
      "$local_jobs -> $scaled_thread_count"
    local_jobs="$scaled_thread_count"
  fi

  echo "$local_jobs"
}
