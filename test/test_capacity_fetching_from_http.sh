#!/bin/bash
# SPDX-License-Identifier: MIT


source "./fake_http.sh"
source "../lib/core.sh"

export DCCSH_SCRIPT_PATH
DCCSH_SCRIPT_PATH="$(readlink -f ../)"
load_core

skip_if "! load_core" "test"


_command() {
  if ! command -v "$1" &>/dev/null; then
    echo "SKIPPING: '$1' is not available!" >&2
    return 1
  fi
  return 0
}

skip_if "! _command netcat" "test"


test_fetch_worker_capacity() {
  local -i port
  port="$(getport)"

  serve_file_http "inputs/basic_stats/single_thread.txt" "$port"
  assert_equals \
    "1/7.5/-1" \
    "$(fetch_worker_capacity "tcp/localhost/0/$port" "tcp/localhost/0/$port")"

  serve_file_http "inputs/basic_stats/8_threads.txt" "$port"
  assert_equals \
    "8/2/-1" \
    "$(fetch_worker_capacity "tcp/localhost/0/$port" "tcp/localhost/0/$port")"

  serve_file_http "inputs/basic_stats/with_dcc_free_mem.txt" "$port"
  assert_equals \
    "8/2/16384" \
    "$(fetch_worker_capacity "tcp/localhost/0/$port" "tcp/localhost/0/$port")"
}

test_fetch_worker_capacity_invalid() {
  local -i port
  port="$(getport)"

  serve_file_http "inputs/basic_stats/invalid_response.txt" "$port"
  local response
  response="$(fetch_worker_capacity \
    "tcp/localhost/0/$port" "tcp/localhost/0/$port")"
  local -ri response_code=$?
  assert_not_equals 0 "$response_code" "Expected non-zero response code."
  assert_equals "" "$response"
}


test_fetch_worker_capacities() {
  local -i port1
  port1="$(getport)"
  serve_file_http "inputs/basic_stats/single_thread.txt" "$port1"

  local -i port2
  port2="$(getport)"
  serve_file_http "inputs/basic_stats/8_threads.txt" "$port2"

  local -i port3
  port3="$(getport)"
  serve_file_http "inputs/basic_stats/invalid_response.txt" "$port3"

  local -i port4
  port4="$(getport)"
  serve_file_http "inputs/basic_stats/with_dcc_free_mem.txt" "$port4"

  assert_equals \
    "tcp/localhost/1/$port1/1/7.5/-1;tcp/localhost/2/$port2/8/2/-1;tcp/localhost/4/$port4/8/2/16384" \
    "$(fetch_worker_capacities \
      "tcp/localhost/1/$port1" \
      "tcp/localhost/2/$port2" \
      "tcp/localhost/3/$port3" \
      "tcp/localhost/4/$port4" \
      )"
}

test_fetch_worker_capacities_with_original_hostspec() {
  local -i port1
  port1="$(getport)"
  serve_file_http "inputs/basic_stats/single_thread.txt" "$port1"

  local -i port2
  port2="$(getport)"
  serve_file_http "inputs/basic_stats/8_threads.txt" "$port2"

  # Test that fetch_worker_capacities() appropriately ignores the
  # "ORIGINAL_HOST_SPECIFICATION" in its input parameter.
  assert_equals \
    "tcp/localhost/1/$port1/1/7.5/-1;tcp/localhost/2/$port2/8/2/-1" \
    "$(fetch_worker_capacities \
      "tcp/localhost/0/0=tcp/localhost/1/$port1" \
      "tcp/localhost/2/$port2")"
}
