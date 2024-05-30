#!/bin/bash
# SPDX-License-Identifier: MIT


source "../distcc-driver-lib.sh"


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
    "tcp/worker-machine-1/3632/3633 tcp/worker-machine-2/3632/3633" \
    "$(parse_distcc_auto_hosts "worker-machine-1 worker-machine-2")"

  assert_equals \
    "tcp/worker-machine-1/1234/3633 tcp/worker-machine-2/1234/3633" \
    "$(parse_distcc_auto_hosts "worker-machine-1:1234 worker-machine-2:1234")"

  assert_equals \
    "tcp/worker-machine-1/1234/5678 tcp/worker-machine-2/1234/5678" \
    "$(parse_distcc_auto_hosts \
      "worker-machine-1:1234:5678 worker-machine-2:1234:5678")"
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
    "tcp/localhost/3632/3633/1/0/1024 tcp/localhost/1234/5678/1/0/1024" \
    "$(scale_worker_job_counts 1024 \
      "tcp/localhost/3632/3633/16/0/1024 tcp/localhost/1234/5678/8/0/1024")"

  assert_equals \
    "" \
    "$(scale_worker_job_counts 2048 \
      "tcp/localhost/3632/3633/16/0/1024 tcp/localhost/1234/5678/8/0/1024")"

  assert_equals \
    "tcp/localhost/3632/3633/5/0/10240" \
    "$(scale_worker_job_counts 2048 \
      "tcp/localhost/3632/3633/16/0/10240 tcp/localhost/1234/5678/8/0/1024")"

  assert_equals \
    "tcp/localhost/1234/5678/5/0/10240" \
    "$(scale_worker_job_counts 2048 \
      "tcp/localhost/3632/3633/16/0/1024 tcp/localhost/1234/5678/8/0/10240")"
}
