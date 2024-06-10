#!/bin/bash
# SPDX-License-Identifier: MIT


source "../distcc.sh"


_command() {
  if ! command -v "$1" &>/dev/null; then
    echo "SKIPPING: '""$1""' is not available!" >&2
    return 1
  fi
  return 0
}

skip_if "! _command docker || ! _command netcat || ! _command ssh" "test"


IMAGE="distcc-driver-ssh-test"
CONTAINER="distcc-driver-ssh-test-test-1"

setup_suite() {
  if ! _command "docker"; then
    return
  fi

  # Build and start a Docker container.
  docker build \
    -t "$IMAGE" \
    "$(pwd)/ssh_tunnel_test_docker/"

  docker run \
    --detach \
    --publish "2222:2222/tcp" \
    --publish "6362:6362/tcp" \
    --name "$CONTAINER" \
    "$IMAGE"

  docker logs -f "$CONTAINER" >&2 &
  sleep 5
}

teardown_suite() {
  if ! _command "docker"; then
    return
  fi

  # Clean up the Docker artefacts.
  docker kill "$CONTAINER"
  docker rm "$CONTAINER"
  docker rmi "$IMAGE"
}


write_netcat_response() {
  local -ri port="$1"
  local -r tempfile="$2"

  netcat -N -w 2 \
      localhost "$port" \
    | dd bs=1 count=64 status=none \
    | head -n 1 \
    > "$tempfile" \
    &
  local -ri netcat_pid=$!
  declare -p netcat_pid >&2

  sleep 5
  echo "$netcat_pid"
}


test_docker_ssh_raw_connection_to_dummy_server() {
  echo '' >&2

  local container_id
  container_id="$(docker ps -aqf "name=$CONTAINER")"
  assert_matches ".+" "$container_id"

  # Check if the server responds directly.
  local -r tempfile="$(mktemp)"
  local -i netcat_pid
  netcat_pid="$(write_netcat_response 6362 "$tempfile")"

  local response
  response="$(cat "$tempfile")"
  rm "$tempfile"

  declare -p response >&2

  assert_status_code 1 "ps \"$netcat_pid\""
  assert_matches "\"Hello, World!\" from: [a-zA-Z0-9]{12,}" "$response"
  assert_matches "from: $container_id" "$response"
}


test_docker_ssh_tunnelled_connection() {
  echo '' >&2

  local output
  # Port 6363 (the stats port) is **not** exposed by the container, and is
  # only available through the SSH tunnel.
  # Assume that if we can successfully query the stats this way, then the
  # tunnel-building code works.
  output="$( \
    DISTCC_AUTO_HOSTS="ssh://root@localhost:2222/6362/6363" \
    DISTCC_AUTO_EARLY_LOCAL_JOBS=0 \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=0 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=0 \
      distcc_build \
        "echo" \
    )"
  local build_code=$?

  assert_equals "0" "$build_code" \
    "Output status code of distcc_build is non-zero!"
  assert_equals "-j $(date +"%Y%m%d")" "$output"

  assert_status_code 1 \
    "pgrep -f \"ssh.*-L.*6362.*-L.*6363\"" \
    "The tunnel should have been destroyed by the driver script after execution!"
}
