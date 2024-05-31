#!/bin/bash
# SPDX-License-Identifier: MIT


source "../distcc-driver-lib.sh"


function _getport {
  # Returns a random port that is likely to be usable as a listening server.

  local port=0
  while true; do
    port="$(( ( (RANDOM << 15) | RANDOM ) % 63001 + 2000))"
    echo "World!" | netcat -Nl "$port" >/dev/null &
    local nc_pid=$!
    sleep 1

    if ps "$nc_pid" >/dev/null; then
      # We found a port that **likely** works!
      echo "Hello, " | netcat localhost "$port" >/dev/null
      break
    fi
  done

  # Return value.
  echo "$port"
}


function _serve_file_http {
  # Serves the content of file $1 over HTTP port $2.

  cat <<EOS | netcat -Nl "$2" >/dev/null &
HTTP/1.1 200 OK
Content-Type: text/plain
Connection: close

$(cat "$1")
EOS

  # echo "Serving '""$1""' on :$2, PID $!" >&2
  sleep 2
}


test_fetch_worker_capacity() {
  local port
  port="$(_getport)"

  _serve_file_http "inputs/test_stats/single_thread.txt" "$port"
  assert_equals \
    "1/7.5/-1" \
    "$(fetch_worker_capacity "tcp/localhost/0/$port")"

  _serve_file_http "inputs/test_stats/8_threads.txt" "$port"
  assert_equals \
    "8/2/-1" \
    "$(fetch_worker_capacity "tcp/localhost/0/$port")"
}


test_fetch_worker_capacities() {
  local port1
  port1="$(_getport)"
  _serve_file_http "inputs/test_stats/single_thread.txt" "$port1"

  local port2
  port2="$(_getport)"
  _serve_file_http "inputs/test_stats/8_threads.txt" "$port2"

  assert_equals \
    "tcp/localhost/1/$port1/1/7.5/-1;tcp/localhost/2/$port2/8/2/-1" \
    "$(fetch_worker_capacities \
      "tcp/localhost/1/$port1" \
      "tcp/localhost/2/$port2")"
}
