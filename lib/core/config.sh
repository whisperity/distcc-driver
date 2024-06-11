#!/bin/bash
# SPDX-License-Identifier: MIT


_dccsh_default_distcc_port=3632
_dccsh_default_stats_port=3633


# Set up variables that are holding the default value for the user-configurable
# options.
_dccsh_default_DISTCC_AUTO_COMPILER_MEMORY=1024
_dccsh_default_DISTCC_AUTO_EARLY_LOCAL_JOBS=0
_dccsh_default_DISTCC_AUTO_FALLBACK_LOCAL_JOBS="$(nproc)"
_dccsh_default_DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS="$(nproc)"


function print_configuration {
  # Print the input configuration options that are relevant for debugging.
  if [ -z "$DCCSH_DEBUG" ]; then
    return
  fi

  debug "DISTCC_AUTO_HOSTS:                       " \
    "$DISTCC_AUTO_HOSTS"

  debug "DISTCC_AUTO_COMPILER_MEMORY:             " \
    "$DISTCC_AUTO_COMPILER_MEMORY"
  if [ -z "$DISTCC_AUTO_COMPILER_MEMORY" ]; then
    debug "    (default):                           " \
      "$_dccsh_default_DISTCC_AUTO_COMPILER_MEMORY"
  fi

  debug "DISTCC_AUTO_EARLY_LOCAL_JOBS:            " \
    "$DISTCC_AUTO_EARLY_LOCAL_JOBS"
  if [ -z "$DISTCC_AUTO_EARLY_LOCAL_JOBS" ]; then
    debug "    (default):                           " \
      "$_dccsh_default_DISTCC_AUTO_EARLY_LOCAL_JOBS"
  fi

  debug "DISTCC_AUTO_FALLBACK_LOCAL_JOBS:         " \
    "$DISTCC_AUTO_FALLBACK_LOCAL_JOBS"
  if [ -z "$DISTCC_AUTO_FALLBACK_LOCAL_JOBS" ]; then
    debug "    (default):                           " \
      "$_dccsh_default_DISTCC_AUTO_FALLBACK_LOCAL_JOBS"
  fi

  debug "DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS:" \
    "$DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS"
  if [ -z "$DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS" ]; then
    debug "    (default):                           " \
      "$_dccsh_default_DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS"
  fi
}


# Getters for configuration options that might have a default.

function distcc_default_port {
  echo "$_dccsh_default_distcc_port"
}

function distcc_default_stats_port {
  echo "$_dccsh_default_stats_port"
}

function distcc_auto_compiler_memory {
  echo "${DISTCC_AUTO_COMPILER_MEMORY:-"$_dccsh_default_DISTCC_AUTO_COMPILER_MEMORY"}"
}

function distcc_auto_early_local_jobs {
  echo "${DISTCC_AUTO_EARLY_LOCAL_JOBS:-"$_dccsh_default_DISTCC_AUTO_EARLY_LOCAL_JOBS"}"
}

function distcc_auto_fallback_local_jobs {
  echo "${DISTCC_AUTO_FALLBACK_LOCAL_JOBS:-"$_dccsh_default_DISTCC_AUTO_FALLBACK_LOCAL_JOBS"}"
}

function distcc_auto_preprocessor_saturation_jobs {
  echo "${DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS:-"$_dccsh_default_DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS"}"
}


function concatenate_config_unset_directives {
  # Generates "--unset=X --unset=Y" directives for the DISTCC_AUTO_* environment
  # variables to be used with 'env'.

  local -ra vars=( \
    "DISTCC_AUTO_HOSTS" \
    "DISTCC_AUTO_COMPILER_MEMORY" \
    "DISTCC_AUTO_EARLY_LOCAL_JOBS" \
    "DISTCC_AUTO_FALLBACK_LOCAL_JOBS" \
    "DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS" \
    )

  for var in "${vars[@]}"; do
    echo -n "--unset=$var "
  done
}
