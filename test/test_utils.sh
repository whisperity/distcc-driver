#!/bin/bash
# SPDX-License-Identifier: MIT


source "../distcc-driver-lib.sh"


test_array() {
  assert_equals "" "$(array '/' "")"
  assert_equals "foo" "$(array '/' "foo")"
  assert_equals "foo/bar" "$(array '/' "foo" "bar")"
  assert_equals "foo/bar/baz" "$(array '/' "foo" "bar" "baz")"

  assert_fails "array '/' \"foo/bar\""
  assert_fails "array '/' \"foo,bar\" \"baz\" \"1/2\""
  assert_equals "foo,bar/baz" "$(array '/' "foo,bar" "baz")"


  assert_equals "" "$(array ',' "")"
  assert_equals "foo" "$(array ',' "foo")"
  assert_equals "foo,bar" "$(array ',' "foo" "bar")"
  assert_equals "foo,bar,baz" "$(array ',' "foo" "bar" "baz")"

  assert_fails "array ',' \"foo,bar\""
  assert_fails "array ',' \"foo/bar\" \"baz\" \"1,2\""
  assert_equals "foo/bar,baz" "$(array ',' "foo/bar" "baz")"
}
