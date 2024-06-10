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
#
# SUMMARY
#
#   Automatically distribute a C/C++ compilation over a DistCC-based cluster
#   with job-count load balancing.
#
#   export DISTCC_AUTO_HOSTS="worker-1 worker-2 worker-3"
#   source distcc.zsh; distcc_build make target1 target2...
#
#
# DESCRIPTION
#
#   This script trivially forwards the execution of the target commands to a
#   Bash shell and the implementation present in 'distcc.sh'.
#
#   See documentation of 'distcc.sh'.
#
#
# CONFIGURATION ENVIRONMENT VARIABLES
#
#   See documentation of 'distcc.sh'.
#
#
# EXIT CODES
#
#   See documentation of 'distcc.sh'.
#
#
# AUTHOR
#
#    @Whisperity <whisperity-packages@protonmail.com>
#
################################################################################


# Determines the location where the currently loaded script is.
# Needed to accurately source the actual code when distcc_build is called.
_DCCSH_SCRIPT_PATH="${0:A:h}"


function distcc_build() {
  # A simple wrapper that forwards execution to the Bash implementation.

  exec bash -c "source ${_DCCSH_SCRIPT_PATH}/distcc.sh; distcc_build $*"
}
