#!/bin/bash
# SPDX-License-Identifier: MIT


source "./fake_http.sh"
source "../distcc.sh"


execution_no_command() {
  distcc_build
}

test_execution_no_command() {
  assert_status_code 96 execution_no_command
}


execution_no_auto_hosts() {
  distcc_build "echo"
}

test_execution_no_auto_hosts() {
  assert_status_code 96 execution_no_auto_hosts
}


execution_local_only() {
  DISTCC_AUTO_HOSTS="non-existent" \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=4 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=0 \
    distcc_build \
      "$@"
}

test_execution_local_only() {
  assert_status_code 0 "execution_local_only \"echo\""
  assert_equals "-j 4" "$(execution_local_only "echo")"
}

test_execution_supports_driving_through_ccache() {
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
  assert_status_code 0 execution_local_only_with_preprocessor
  assert_equals "-j 4" "$(execution_local_only_with_preprocessor)"
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
    "DISTCC_HOSTS=localhost/2 --localslots=2 localhost:1234/8,lzo" \
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
    "DISTCC_HOSTS=localhost/2 --localslots=2 --localslots_cpp=3 localhost:1234/8,lzo" \
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
    "DISTCC_HOSTS=localhost:5678/8,lzo localhost:1234/1,lzo" \
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
    "DISTCC_HOSTS=localhost:5678/8,lzo" \
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
    "DISTCC_HOSTS=localhost:1234/1,lzo" \
    "$(execution_two_fake_remotes_big_missing \
      "./no_job_arg_entry.sh env | grep DISTCC")"
}
