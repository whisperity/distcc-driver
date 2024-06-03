#!/bin/bash
# SPDX-License-Identifier: MIT


source "./fake_http.sh"
source "../distcc-driver-lib.sh"


test_fetch_worker_capacity() {
  local port
  port="$(_getport)"

  _serve_file_http "inputs/basic_stats/single_thread.txt" "$port"
  assert_equals \
    "1/7.5/-1" \
    "$(fetch_worker_capacity "tcp/localhost/0/$port")"

  _serve_file_http "inputs/basic_stats/8_threads.txt" "$port"
  assert_equals \
    "8/2/-1" \
    "$(fetch_worker_capacity "tcp/localhost/0/$port")"
}


test_fetch_worker_capacities() {
  local port1
  port1="$(_getport)"
  _serve_file_http "inputs/basic_stats/single_thread.txt" "$port1"

  local port2
  port2="$(_getport)"
  _serve_file_http "inputs/basic_stats/8_threads.txt" "$port2"

  assert_equals \
    "tcp/localhost/1/$port1/1/7.5/-1;tcp/localhost/2/$port2/8/2/-1" \
    "$(fetch_worker_capacities \
      "tcp/localhost/1/$port1" \
      "tcp/localhost/2/$port2")"
}
