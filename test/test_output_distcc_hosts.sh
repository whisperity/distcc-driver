#!/bin/bash
# SPDX-License-Identifier: MIT


source "./fake_http.sh"
source "../distcc.sh"


declare localhost_ip=""

setup_suite() {
  localhost_ip="$(ip address show dev lo \
    | grep -Po 'inet \K.*?(?=[/ ])')"
  echo "Assuming \"localhost\" is: \"$localhost_ip\" ..." >&2
}

teardown_suite() {
  unset localhost_ip
}


test_execution_no_command() {
  assert_status_code 96 "distcc_build"
}


test_execution_no_auto_hosts() {
  assert_status_code 96 "distcc_build \"echo\""
}


execution_local_only() {
  DISTCC_AUTO_HOSTS="non-existent" \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=4 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=0 \
    distcc_build \
      "$@"
}

test_execution_local_only() {
  local output
  output="$(execution_local_only "echo")"
  local -ri exit_code=$?

  assert_equals 0 "$exit_code" "Expected success (0) exit code."
  assert_equals "-j 4" "$output"
}

test_execution_local_only_sets_ccache_prefix() {
  assert_equals \
    "CCACHE_PREFIX=distcc" \
    "$(execution_local_only "./no_job_arg_entry.sh env | grep CCACHE_PREFIX")"
}


execution_local_only_with_preprocessor() {
  DISTCC_AUTO_HOSTS="non-existent" \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=4 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=8 \
    distcc_build "echo"
}

test_execution_local_only_with_preprocessor() {
  local output
  output="$(execution_local_only_with_preprocessor)"
  local -ri exit_code=$?

  assert_equals 0 "$exit_code" "Expected success (0) exit code."
  assert_equals "-j 4" "$output"
}


execution_fake_remote_exists() {
  local port
  port="$(_getport)"
  _serve_file_http "inputs/basic_stats/8_threads.txt" "$port"

  DISTCC_AUTO_HOSTS="localhost:1234:$port" \
    DISTCC_AUTO_EARLY_LOCAL_JOBS=2 \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=4 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=0 \
    distcc_build \
      "$@"
}

test_execution_fake_remote_exists() {
  assert_equals "-j 10" "$(execution_fake_remote_exists "echo")"
  assert_equals \
    "DISTCC_HOSTS=localhost/2 --localslots=2 $localhost_ip:1234/8,lzo" \
    "$(execution_fake_remote_exists "./no_job_arg_entry.sh env | grep DISTCC")"
}

execution_fake_remote_exists_with_preprocessor() {
  local port
  port="$(_getport)"
  _serve_file_http "inputs/basic_stats/8_threads.txt" "$port"

  DISTCC_AUTO_HOSTS="localhost:1234:$port" \
    DISTCC_AUTO_EARLY_LOCAL_JOBS=2 \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=4 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=3 \
    distcc_build \
      "$@"
}

test_execution_fake_remote_exists_with_preprocessor() {
  assert_equals \
    "-j 13" \
    "$(execution_fake_remote_exists_with_preprocessor "echo")"
  assert_equals \
    "DISTCC_HOSTS=localhost/2 --localslots=2 --localslots_cpp=3 $localhost_ip:1234/8,lzo" \
    "$(execution_fake_remote_exists_with_preprocessor \
      "./no_job_arg_entry.sh env | grep DISTCC")"

}

test_execution_fake_remote_exists_with_preprocessor_cleans_environment() {
  assert_equals \
    "" \
    "$(execution_fake_remote_exists_with_preprocessor \
      "./no_job_arg_entry.sh env | grep -i DISTCC_AUTO")"
  assert_equals \
    "" \
    "$(execution_fake_remote_exists_with_preprocessor \
      "./no_job_arg_entry.sh env | grep -i DCCSH")"
}

execution_fake_remote_does_not_exist() {
  local port
  port="$(_getport)"

  DISTCC_AUTO_HOSTS="localhost:1234:$port" \
    DISTCC_AUTO_EARLY_LOCAL_JOBS=2 \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=4 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=0 \
    distcc_build \
      "$@"
}

test_execution_fake_remote_does_not_exist() {
  assert_equals "-j 4" "$(execution_fake_remote_does_not_exist "echo")"
  assert_equals \
    "DISTCC_HOSTS=localhost/4 --localslots=4" \
    "$(execution_fake_remote_does_not_exist \
      "./no_job_arg_entry.sh env | grep DISTCC")"
}


execution_two_fake_remotes_both_exist() {
  local port1
  port1="$(_getport)"
  _serve_file_http "inputs/basic_stats/single_thread.txt" "$port1"

  local port2
  port2="$(_getport)"
  _serve_file_http "inputs/basic_stats/8_threads.txt" "$port2"


  DISTCC_AUTO_HOSTS="localhost:1234:$port1 localhost:5678:$port2" \
    DISTCC_AUTO_EARLY_LOCAL_JOBS=0 \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=2 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=0 \
    distcc_build \
      "$@"
}

test_execution_two_fake_remotes_both_exist() {
  assert_equals "-j 9" "$(execution_two_fake_remotes_both_exist "echo")"
  assert_equals \
    "DISTCC_HOSTS=$localhost_ip:5678/8,lzo $localhost_ip:1234/1,lzo" \
    "$(execution_two_fake_remotes_both_exist \
      "./no_job_arg_entry.sh env | grep DISTCC")"
}

execution_two_fake_remotes_small_missing() {
  local port1
  port1="$(_getport)"

  local port2
  port2="$(_getport)"
  _serve_file_http "inputs/basic_stats/8_threads.txt" "$port2"

  DISTCC_AUTO_HOSTS="localhost:1234:$port1 localhost:5678:$port2" \
    DISTCC_AUTO_EARLY_LOCAL_JOBS=0 \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=2 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=0 \
    distcc_build \
      "$@"
}

test_execution_two_fake_remotes_small_missing() {
  assert_equals "-j 8" "$(execution_two_fake_remotes_small_missing "echo")"
  assert_equals \
    "DISTCC_HOSTS=$localhost_ip:5678/8,lzo" \
    "$(execution_two_fake_remotes_small_missing \
      "./no_job_arg_entry.sh env | grep DISTCC")"
}

execution_two_fake_remotes_big_missing() {
  local port1
  port1="$(_getport)"
  _serve_file_http "inputs/basic_stats/single_thread.txt" "$port1"

  local port2
  port2="$(_getport)"

  DISTCC_AUTO_HOSTS="localhost:1234:$port1 localhost:5678:$port2" \
    DISTCC_AUTO_EARLY_LOCAL_JOBS=0 \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=2 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=0 \
    distcc_build \
      "$@"
}

test_execution_two_fake_remotes_big_missing() {
  assert_equals "-j 1" "$(execution_two_fake_remotes_big_missing "echo")"
  assert_equals \
    "DISTCC_HOSTS=$localhost_ip:1234/1,lzo" \
    "$(execution_two_fake_remotes_big_missing \
      "./no_job_arg_entry.sh env | grep DISTCC")"
}
