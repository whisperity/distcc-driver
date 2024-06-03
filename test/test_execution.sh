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
    distcc_build "echo"
}

test_execution_local_only() {
  assert_status_code 0 execution_local_only
  assert_equals "-j 4" "$(execution_local_only)"
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
  _serve_file_http "inputs/test_stats/8_threads.txt" "$port"

  DISTCC_AUTO_HOSTS="localhost:1234:$port" \
    DISTCC_AUTO_EARLY_LOCAL_JOBS=2 \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=4 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=0 \
    distcc_build "$@"
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
  _serve_file_http "inputs/test_stats/8_threads.txt" "$port"

  DISTCC_AUTO_HOSTS="localhost:1234:$port" \
    DISTCC_AUTO_EARLY_LOCAL_JOBS=2 \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=4 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=3 \
    distcc_build "$@"
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

execution_fake_remote_does_not_exist() {
  local port
  port="$(_getport)"

  DISTCC_AUTO_HOSTS="localhost:1234:$port" \
    DISTCC_AUTO_EARLY_LOCAL_JOBS=2 \
    DISTCC_AUTO_FALLBACK_LOCAL_JOBS=4 \
    DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS=0 \
    distcc_build "$@"
}

test_execution_fake_remote_does_not_exist() {
  assert_equals "-j 4" "$(execution_fake_remote_does_not_exist "echo")"
  assert_equals \
    "DISTCC_HOSTS=localhost/4 --localslots=4" \
    "$(execution_fake_remote_does_not_exist \
      "./no_job_arg_entry.sh env | grep DISTCC")"
}
