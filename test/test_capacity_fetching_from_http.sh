#!/bin/bash
# SPDX-License-Identifier: MIT


source "./fake_http.sh"
source "../lib/driver.sh"


test_fetch_worker_capacity() {
  local port
  port="$(_getport)"

  _serve_file_http "inputs/basic_stats/single_thread.txt" "$port"
  assert_equals \
    "1/7.5/-1" \
    "$(fetch_worker_capacity "tcp/localhost/0/$port" "tcp/localhost/0/$port")"

  _serve_file_http "inputs/basic_stats/8_threads.txt" "$port"
  assert_equals \
    "8/2/-1" \
    "$(fetch_worker_capacity "tcp/localhost/0/$port" "tcp/localhost/0/$port")"
}

test_fetch_worker_capacity_invalid() {
  local port
  port="$(_getport)"

  _serve_file_http "inputs/basic_stats/invalid_response.txt" "$port"
  local response
  response="$(fetch_worker_capacity \
    "tcp/localhost/0/$port" "tcp/localhost/0/$port")"
  local -ri response_code=$?
  assert_not_equals 0 "$response_code" "Expected non-zero response code."
  assert_equals "" "$response"
}


test_fetch_worker_capacities() {
  local port1
  port1="$(_getport)"
  _serve_file_http "inputs/basic_stats/single_thread.txt" "$port1"

  local port2
  port2="$(_getport)"
  _serve_file_http "inputs/basic_stats/8_threads.txt" "$port2"

  local port3
  port3="$(_getport)"
  _serve_file_http "inputs/basic_stats/invalid_response.txt" "$port3"

  assert_equals \
    "tcp/localhost/1/$port1/1/7.5/-1;tcp/localhost/2/$port2/8/2/-1" \
    "$(fetch_worker_capacities \
      "tcp/localhost/1/$port1" \
      "tcp/localhost/2/$port2" \
      "tcp/localhost/3/$port3")"
}

test_fetch_worker_capacities_with_original_hostspec() {
  local port1
  port1="$(_getport)"
  _serve_file_http "inputs/basic_stats/single_thread.txt" "$port1"

  local port2
  port2="$(_getport)"
  _serve_file_http "inputs/basic_stats/8_threads.txt" "$port2"

  # Test that fetch_worker_capacities() appropriately ignores the
  # "ORIGINAL_HOST_SPECIFICATION" in its input parameter.
  assert_equals \
    "tcp/localhost/1/$port1/1/7.5/-1;tcp/localhost/2/$port2/8/2/-1" \
    "$(fetch_worker_capacities \
      "tcp/localhost/0/0=tcp/localhost/1/$port1" \
      "tcp/localhost/2/$port2")"
}
