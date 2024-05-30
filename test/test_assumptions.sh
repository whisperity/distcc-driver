#!/bin/bash
# SPDX-License-Identifier: MIT


test_core_utility_free() {
  free -m 1>&2
  local mem="$(free -m | grep "^Mem:" | awk '{ print $7 }')"
  echo "Available RAM understood as: \"$mem\"" >&2
  assert "test $mem -gt 0" "Available memory should be non-zero and output"
}
