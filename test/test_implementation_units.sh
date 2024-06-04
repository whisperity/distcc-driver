#!/bin/bash
# SPDX-License-Identifier: MIT


source "../lib/driver.sh"
source "../lib/ssh.sh"


declare localhost_ip=""

setup_suite() {
  localhost_ip="$(ip address show dev lo \
    | grep -Po 'inet \K.*?(?=[/ ])')"
  echo "Assuming \"localhost\" is: \"$localhost_ip\" ..." >&2
}

teardown_suite() {
  unset localhost_ip
}


test_parse_distcc_auto_hosts() {
  assert_equals \
    "tcp/localhost.com/3632/3633" \
    "$(parse_distcc_auto_hosts localhost.com)"

  assert_equals \
    "tcp/localhost.com/1234/5678" \
    "$(parse_distcc_auto_hosts localhost.com:1234:5678)"

  assert_equals \
    "tcp/example.org/1/3633" \
    "$(parse_distcc_auto_hosts tcp://example.org:1)"

  assert_equals \
    "tcp/example.org/1/2" \
    "$(parse_distcc_auto_hosts tcp://example.org:1:2)"

  assert_equals \
    "tcp/worker-machine-1/3632/3633;tcp/worker-machine-2/3632/3633" \
    "$(parse_distcc_auto_hosts "worker-machine-1 worker-machine-2")"

  assert_equals \
    "tcp/worker-machine-1/1234/3633;tcp/worker-machine-2/1234/3633" \
    "$(parse_distcc_auto_hosts "worker-machine-1:1234 worker-machine-2:1234")"

  assert_equals \
    "tcp/worker-machine-1/1234/5678;tcp/worker-machine-2/1234/5678" \
    "$(parse_distcc_auto_hosts \
      "worker-machine-1:1234:5678 worker-machine-2:1234:5678")"

  assert_equals \
    "" \
    "$(parse_distcc_auto_hosts "unknown://example.com")"

  assert_equals \
    "tcp/$localhost_ip/3632/3633;ssh/localhost/3632/3633" \
    "$(parse_distcc_auto_hosts "localhost ssh://localhost")"

  assert_equals \
    "tcp/$localhost_ip/3632/3633;ssh/user@localhost:2222/3632/3633" \
    "$(parse_distcc_auto_hosts "localhost ssh://user@localhost:2222")"

  assert_equals \
    "tcp/$localhost_ip/3632/3633;ssh/user@localhost:2222/1234/3633" \
    "$(parse_distcc_auto_hosts "localhost ssh://user@localhost:2222/1234")"

  assert_equals \
    "tcp/$localhost_ip/3632/3633;ssh/user@localhost:2222/1234/5678" \
    "$(parse_distcc_auto_hosts "localhost ssh://user@localhost:2222/1234/5678")"
}


test_unique_host_specifications() {
  assert_equals \
    "tcp/localhost/3632/3633;tcp/localhost/1234/5678;tcp/example.com/80/443" \
    "$(unique_host_specifications \
      "tcp/localhost/3632/3633" \
      "tcp/localhost/1234/5678" \
      "tcp/localhost/3632/3633" \
      "tcp/localhost/1234/5678" \
      "tcp/example.com/80/443" \
      "tcp/localhost/3632/3633")"
}


test_scale_worker_job_counts() {
  assert_equals \
    "tcp/localhost/3632/3633/16/0/-1" \
    "$(scale_worker_job_counts 20480 "tcp/localhost/3632/3633/16/0/-1")"

  assert_equals \
    "tcp/localhost/3632/3633/16/0/8192" \
    "$(scale_worker_job_counts 0 "tcp/localhost/3632/3633/16/0/8192")"

  assert_equals \
    "tcp/localhost/3632/3633/16/0/-1" \
    "$(scale_worker_job_counts 10240 "tcp/localhost/3632/3633/16/0/-1")"

  assert_equals \
    "tcp/localhost/3632/3633/1/0/1024" \
    "$(scale_worker_job_counts 1024 "tcp/localhost/3632/3633/16/0/1024")"

  assert_equals \
    "tcp/localhost/3632/3633/1/0/1024;tcp/localhost/1234/5678/1/0/1024" \
    "$(scale_worker_job_counts 1024 \
      "tcp/localhost/3632/3633/16/0/1024" "tcp/localhost/1234/5678/8/0/1024")"

  assert_equals \
    "" \
    "$(scale_worker_job_counts 2048 \
      "tcp/localhost/3632/3633/16/0/1024" "tcp/localhost/1234/5678/8/0/1024")"

  assert_equals \
    "tcp/localhost/3632/3633/5/0/10240" \
    "$(scale_worker_job_counts 2048 \
      "tcp/localhost/3632/3633/16/0/10240" "tcp/localhost/1234/5678/8/0/1024")"

  assert_equals \
    "tcp/localhost/1234/5678/5/0/10240" \
    "$(scale_worker_job_counts 2048 \
      "tcp/localhost/3632/3633/16/0/1024" "tcp/localhost/1234/5678/8/0/10240")"
}


test_sum_worker_job_counts() {
  assert_equals \
    "16" \
    "$(sum_worker_job_counts "tcp/localhost/3632/3633/16/0/-1")"

  assert_equals \
    "16" \
    "$(sum_worker_job_counts "tcp/localhost/3632/3633/16/0/8192")"

  assert_equals \
    "16" \
    "$(sum_worker_job_counts "tcp/localhost/3632/3633/16/0/-1")"

  assert_equals \
    "16" \
    "$(sum_worker_job_counts "tcp/localhost/3632/3633/16/0/1024")"

  assert_equals \
    "24" \
    "$(sum_worker_job_counts \
      "tcp/localhost/3632/3633/16/0/1024" "tcp/localhost/1234/5678/8/0/1024")"

  assert_equals \
    "24" \
    "$(sum_worker_job_counts \
      "tcp/localhost/3632/3633/16/0/1024" "tcp/localhost/1234/5678/8/0/1024")"

  assert_equals \
    "24" \
    "$(sum_worker_job_counts \
      "tcp/localhost/3632/3633/16/0/10240" "tcp/localhost/1234/5678/8/0/1024")"

  assert_equals \
    "24" \
    "$(sum_worker_job_counts \
      "tcp/localhost/3632/3633/16/0/1024" "tcp/localhost/1234/5678/8/0/10240")"

  assert_equals \
    "32" \
    "$(sum_worker_job_counts \
      "tcp/localhost/3632/3633/16/0/1024" "tcp/localhost/1234/5678/8/0/10240" \
      "tcp/localhost/8888/9999/8/0/0")"
}


test_scale_local_job_count() {
  assert_equals 0 "$(scale_local_job_count 0 1024 10240)"
  assert_equals 10 "$(scale_local_job_count 16 1024 10240)"
  assert_equals 16 "$(scale_local_job_count 16 1024 0)"
  assert_equals 16 "$(scale_local_job_count 16 0 0)"
  assert_equals 16 "$(scale_local_job_count 16 0 10240)"

  assert_equals 8 "$(scale_local_job_count 8 1024 10240)"
  assert_equals 5 "$(scale_local_job_count 8 2048 10240)"
}


test_transform_workers_by_priority() {
  local worker_4j_5l_4g="tcp/localhost/1000/2000/4/5/4096"
  local worker_4j_5l_8g="tcp/localhost/1001/2002/4/5/8192"
  local worker_8j_2l_16g="tcp/localhost/1002/2002/8/2/16384"
  local worker_8j_2l_32g="tcp/localhost/1003/2003/8/2/32768"
  local worker_8j_6l_16g="tcp/localhost/1004/2004/8/6/16384"
  local worker_16j_100l_32g="tcp/localhost/1005/2005/16/100/32768"

  local expected
  expected="$(array ';' \
    "$worker_16j_100l_32g" \
    "$worker_8j_2l_32g" \
    "$worker_8j_2l_16g" \
    "$worker_8j_6l_16g" \
    "$worker_4j_5l_8g" \
    "$worker_4j_5l_4g" \
    )"

  assert_equals \
    "$expected" \
    "$(transform_workers_by_priority \
      "$worker_4j_5l_4g" \
      "$worker_4j_5l_8g" \
      "$worker_8j_2l_16g" \
      "$worker_8j_2l_32g" \
      "$worker_8j_6l_16g" \
      "$worker_16j_100l_32g" \
      )"
}
