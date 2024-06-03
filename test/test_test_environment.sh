#!/bin/bash
# SPDX-License-Identifier: MIT


test_core_utility_free() {
  free -m 1>&2
  local mem
  mem="$(free -m | grep "^Mem:" | awk '{ print $7 }')"
  echo "Available RAM understood as: \"$mem\"" >&2
  assert "test $mem -gt 0" "Available memory should be non-zero and output"
}


test_fake_entry_jobs_arg_remover() {
  assert_equals "x" "$(./no_job_arg_entry.sh echo x)"
  assert_equals "x y" "$(./no_job_arg_entry.sh echo x y)"
  assert_equals "x y" "$(./no_job_arg_entry.sh echo x y -j 8)"
  assert_equals "x y" "$(./no_job_arg_entry.sh echo -j 8 x y)"
  assert_equals "x y" "$(./no_job_arg_entry.sh echo x -j 8 y)"
}
