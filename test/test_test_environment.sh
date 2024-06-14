#!/bin/bash
# SPDX-License-Identifier: MIT


test_core_utility_free() {
  free -m 1>&2
  local mem
  mem="$(free -m | grep "^Mem:" | awk '{ print $7 }')"
  echo "Available RAM understood as: \"$mem\"" >&2
  assert "test $mem -gt 0" "Available memory should be non-zero and output"
}


test_script_no_job_arg() {
  assert_equals "x" "$(./no_job_arg.sh echo x)"
  assert_equals "x y" "$(./no_job_arg.sh echo x y)"
  assert_equals "x y" "$(./no_job_arg.sh echo x y -j 8)"
  assert_equals "x y" "$(./no_job_arg.sh echo -j 8 x y)"
  assert_equals "x y" "$(./no_job_arg.sh echo x -j 8 y)"

  local -i random_number="$(( RANDOM ))"
  assert_equals "TEST_VARIABLE=$random_number" \
    "$(TEST_VARIABLE="$random_number" \
      ./no_job_arg.sh \
        "env | grep \"TEST_VARIABLE\"" \
      )"

  assert_equals "TEST_VARIABLE=$random_number" \
    "$(TEST_VARIABLE="$random_number" \
      ./no_job_arg.sh \
        "env | grep \"TEST_VARIABLE\"" "-j" "8" \
      )"

  # These invocations are not supported.
  assert_fails \
    "$(TEST_VARIABLE="$random_number" \
      ./no_job_arg.sh \
        "env -j 8 | grep \"TEST_VARIABLE\"" \
      )"

  assert_fails \
    "$(TEST_VARIABLE="$random_number" \
      ./no_job_arg.sh \
        "env | grep \"TEST_VARIABLE\" -j 8" \
      )"
}
