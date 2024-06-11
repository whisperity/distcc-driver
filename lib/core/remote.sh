#!/bin/bash
# SPDX-License-Identifier: MIT


_dccsh_stat_connection_timeout=5
_dccsh_stat_max_request_time=10


function fetch_worker_capacities {
  # Download and assemble the worker capacities for all the hosts specified in
  # the variadic parameter list $@.
  # Returns the worker host specifications concatenated with the capacity
  # information for each array element, in the same semicolon (';') separated
  # format as with parse_distcc_auto_hosts.

  local -a workers=()

  for hostspec in "$@"; do
    local -a hostspec_and_original_hostspec
    local -a hostspec_fields
    local original_hostspec
    IFS='=' read -ra hostspec_and_original_hostspec <<< "$hostspec"
    if [ "${#hostspec_and_original_hostspec[@]}" -eq 2 ]; then
      original_hostspec="${hostspec_and_original_hostspec[0]}"
      hostspec="${hostspec_and_original_hostspec[1]}"
    else
      original_hostspec="$hostspec"
    fi

    local worker_capacity
    worker_capacity="$(fetch_worker_capacity \
      "$hostspec" \
      "$original_hostspec")"
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
      debug "Querying host capacity: $original_hostspec FAILED!"
      continue
    fi

    workers+=("$hostspec"/"$worker_capacity")
  done

  array ';' "${workers[@]}"
}


function fetch_worker_capacity {
  # Downloads and parses **one** DistCC host's ($1) "statistics" output to
  # extract the server's capacity and statistical details from it.
  # Optionally, $2 might specify the "ORIGINAL_HOST_SPECIFICATION", but this is
  # only used for debugging purposes.
  #
  # Returns the worker capacity information: "THREAD_COUNT/LOAD_AVG/FREE_MEM".
  # If the capacity could not be fetched because the server sent an invalid
  # response or could not connect, does not emit anything and exits with '1'.

  local hostspec="$1"
  local -r original_hostspec="$2"
  debug "Querying host capacity: $original_hostspec ..."

  local -a original_hostspec_fields
  local -a hostspec_fields
  IFS='/' read -ra original_hostspec_fields <<< "$original_hostspec"
  IFS='/' read -ra hostspec_fields <<< "$hostspec"

  local -r protocol="${hostspec_fields[0]}"
  local -r original_protocol="${original_hostspec_fields[0]}"
  local -r hostname="${hostspec_fields[1]}"
  local -r original_hostname="${original_hostspec_fields[1]}"
  local -r stat_port="${hostspec_fields[3]}"
  local -r original_stat_port="${original_hostspec_fields[3]}"

  local stat_response
  stat_response="$(curl "$hostname:$stat_port" \
    --connect-timeout "$_dccsh_stat_connection_timeout" \
    --max-time "$_dccsh_stat_max_request_time" \
    --silent \
    --show-error)"
  local stat_query_response_code=$?
  local stat_tag_count
  stat_tag_count="$(echo "$stat_response" | grep -c "</\?distccstats>")"
  if [ "$stat_query_response_code" -ne 0 ] || [ "$stat_tag_count" -ne 2 ]; then
    if [ "$stat_query_response_code" -ne 0 ]; then
      log "ERROR" "Failed to query capacities of host" \
        "\"[$original_protocol://$original_hostname]:$original_stat_port\"!" \
        "Likely the host is unavailable." \
        "See curl error message above for details!"
    elif [ "$stat_tag_count" -ne 2 ]; then
      log "ERROR" "Failed to query capacities of host" \
        "\"[$original_protocol://$original_hostname]:$original_stat_port\"!" \
        "Received some response, but it was empty, or invalid!"
    fi

    if [ "$hostspec" != "$original_hostspec" ]; then
      log "NOTE" "The actual query was sent to" \
        "\"[$protocol://$hostname]:$stat_port\"!"
    fi

    debug -e "Raw DistCC --stats response:\n${stat_response}"

    return 1
  fi

  # These statistical fields has been present in the output since the very early
  # days of distcc, see distcc/distcc@d6532ae1d997a31884a67c51ec2bc75756242eed,
  # the initial commit.
  local -i dcc_max_kids
  dcc_max_kids="$(echo "$stat_response" | grep "dcc_max_kids" \
    | cut -d ' ' -f 2)"
  debug "  - Threads: $dcc_max_kids"

  local dcc_loads
  mapfile -t dcc_loads -n 3 < \
    <(echo "$stat_response" | grep "dcc_load" | cut -d ' ' -f 2)
  debug "  - Load: ${dcc_loads[*]}"

  # (Unfortunately, Bash's $(( )) does *NOT* support floats. Zsh would.)
  local dcc_load_average
  dcc_load_average="$(echo "${dcc_loads[@]}" \
    | awk '{ print ($1 + $2 + $3) / 3 }')"
  debug "  - Load avg: $dcc_load_average"

  # Understand the "dcc_free_mem" line in the output **if it exists**, otherwise
  # default to "-1" (for later sorting purposes,
  # see transform_workers_by_priority()).
  #
  # "dcc_free_mem" might not be implemented universally, as it is has been both
  # proposed and implemented in June 2024, see
  #     * http://github.com/distcc/distcc/issues/521
  #     * http://github.com/distcc/distcc/pull/523
  # for details.
  #
  # Until widely available in the oldest LTS Ubuntus (aka. the next decade...),
  # assume that it will **NOT** be available in the general case.
  local -i dcc_free_mem
  local dcc_free_mem_line
  dcc_free_mem_line="$(echo "$stat_response" | grep "dcc_free_mem")"
  # shellcheck disable=SC2181
  if [ $? -eq 0 ]; then
    dcc_free_mem="$(echo "$dcc_free_mem_line" | cut -d ' ' -f 2)"
    debug "  - Memory: $dcc_free_mem MiB"
  else
    dcc_free_mem="-1"
  fi

  array '/' "$dcc_max_kids" "$dcc_load_average" "$dcc_free_mem"
}


function scale_worker_jobs {
  # Calculates how many jobs should be dispatched (at maximum) to each already
  # queried worker in $@ (the variadic input argument), based on the workers'
  # capacities and the expected per-job memory use value passed under $1.

  local -ri requested_per_job_mem="$1"
  shift 1

  if [ "$requested_per_job_mem" -le 0 ]; then
    # Return value.
    echo "$@"
    return
  fi

  local -a workers=()

  for worker_specification in "$@"; do
    local -a worker_specification_fields
    IFS='/' read -ra worker_specification_fields <<< "$worker_specification"

    local -i available_memory="${worker_specification_fields[6]}"
    if [ "$available_memory" == "-1" ]; then
      # If no memory information is available about the worker, assume that it
      # will be able to handle the number of jobs it exposes that it could
      # handle, and do not do any scaling, as we have no way of executing the
      # scaling.
      workers+=("$worker_specification")
      continue
    fi

    local -i thread_count="${worker_specification_fields[4]}"
    local -i \
      scaled_thread_count="$(( available_memory / requested_per_job_mem ))"
    if [ "$scaled_thread_count" -eq 0 ]; then
      debug "Skipping worker (available memory: $available_memory MiB):" \
        "$protocol://$hostname:$job_port"
      continue
    elif [ "$scaled_thread_count" -lt "$thread_count" ]; then
      local protocol="${worker_specification_fields[0]}"
      local hostname="${worker_specification_fields[1]}"
      local -i job_port="${worker_specification_fields[2]}"
      debug "Scaling down worker \"$protocol://$hostname:$job_port\"" \
        "(available memory: $available_memory MiB):" \
        "$thread_count -> $scaled_thread_count"

      worker_specification_fields[4]="$scaled_thread_count"
    fi

    workers+=("$(array '/' "${worker_specification_fields[@]}")")
  done

  array ';' "${workers[@]}"
}


function sum_worker_jobs {
  # Calculates the number of jobs to be dispatched to workers in total, based
  # on the worker specification provided under the variadic input $@.
  # Returns a single integer number.

  local -i remote_job_count=0

  for worker_specification in "$@"; do
    local -a worker_specification_fields
    IFS='/' read -ra worker_specification_fields <<< "$worker_specification"

    local -i worker_job_count="${worker_specification_fields[4]}"
    remote_job_count="$(( remote_job_count + worker_job_count ))"
  done

  echo "$remote_job_count"
}


function sort_workers {
  # Sorts the array of worker specifications, as provided in the variadic input
  # parameter ($@), into a priority list based on the capacities received.
  # Returns the worker specification in the exact same format, just in a
  # different order, in a semicolon (';') separated array.
  #
  # The sorting prioritises servers:
  #   * First, the servers that offer the most available workers.
  #   * Then, for the groups of the same number of jobs, the servers with the
  #     lower calculated load average is prioritised first.
  #   * In case this ordering would still produce multiple head-to-head options,
  #     prioritise the server with the more available RAM (if this information
  #     is reported).
  #
  # Note that during normal function (although this is **NOT** assumed by this
  # implementation), the number of jobs is scaled down based on the available
  # RAM (if reported) anyway.

  # Return value.
  echo -e "$(array '\n' "$@")" \
    | sort -t '/' \
      -k5nr \
      -k6n \
      -k7nr \
    | head -c -1 \
    | tr '\n' ';'
}
