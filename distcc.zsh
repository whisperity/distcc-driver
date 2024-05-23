#!/bin/zsh
# SPDX-License-Identifier: MIT
#
################################################################################
### distcc-driver(1)      DistCC remote auto-job script     distcc-driver(1) ###
#
# NAME
#
#   distcc.zsh
#
# SYNOPSIS
#
#   Automatically distribute a C/C++ compilation over a DistCC-based cluster
#   with job-count load balancing.
#
#   source distcc.zsh; distcc_build make target1 target2...
#
# DESCRIPTION
#
#   This script trivially forwards the execution of the target commands to a
#   Bash shell and the implementation present in 'distcc.sh'.
#
#   See documentation of distcc.sh.
#
# CONFIGURATION ENVIRONMENT VARIABLES
#
#   See documentation of distcc.sh.
#
# EXIT CODES
#
#   See documentation of distcc.sh.
#
# AUTHOR
#
#    @Whisperity <whisperity-packages@protonmail.com>
################################################################################

distcc_build() {
  # A simple wrapper that forwards execution to the Bash implementation.
  bash -c "source ./distcc.sh; distcc_build $*"
}
