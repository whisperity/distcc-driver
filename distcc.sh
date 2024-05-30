#!/bin/bash
# SPDX-License-Identifier: MIT
#
################################################################################
### distcc-driver(1)      DistCC remote auto-job script     distcc-driver(1) ###
#
# NAME
#
#   distcc.sh
#
# SYNOPSIS
#
#   Automatically distribute a C/C++ compilation over a DistCC-based cluster
#   with job-count load balancing.
#
#   source distcc.sh; distcc_build make target1 target2...
#
# DESCRIPTION
#
#   This script allows remotely building C/C++ projects through a distcc(1)
#   cluster.
#   However, instead of requiring the user to manually configure DISTCC_HOSTS,
#   which has a required and non-trivial format (such as specifying the number
#   of jobs to dispatch to a server) and making sure that the called build
#   system is also given an appropriate "--jobs N" parameter, this script
#   automatically balances the available server list, prevents dispatching to
#   servers that do not reply to jobs, and selects the appropriate job count to
#   drive the build with.
#
#   It is expected to call this script by prefixing a build command with the
#   wrapper function's name, by specifying the hosts where distccd(1) servers
#   are listening.
#   The called build tool should allow receiving a "-j" parameter, followed by
#   a number.
#
#     DISTCC_AUTO_HOSTS="server-1 server-2" distcc_build make foo
#
#   In this case, the real call under the hood will expand to something
#   appropriate, such as:
#
#     DISTCC_HOSTS="server-1/16,lzo server-2/8,lzo" make foo -j 24
#
# CONFIGURATION ENVIRONMENT VARIABLES
#
#     DISTCC_HOSTS              The original, official remote worker
#                               "HOST SPECIFICATION" used by DistCC.
#                               This variable is **IGNORED** and **OVERWRITTEN**
#                               by this script!
#
#     DISTCC_AUTO_HOSTS         The list of hosts to check and balance the
#                               running compilation against.
#                               See the exact format below, under
#                               HOST SPECIFICATION.
#                               Compared to DISTCC_HOSTS (**NOT** used by this
#                               script!), the number of available job slots on
#                               the server need not be specified.
#
#     DISTCC_AUTO_COMPILER_MEMORY   The amount of memory use **in MiB** that is
#                                   expected to be consumed by a **single**
#                                   compiler process, on average.
#                                   This value is used to scale the number of
#                                   jobs dispatched to a worker, if such
#                                   calculation is applicable.
#                                   It is usually not necessary to tweak this
#                                   value prior to encountering performance
#                                   issues.
#
#                                   Defaults to a reasonably large value of
#                                   "1024", corresponding to 1 GiB of memory.
#                                   (This value was empyrically verified to be
#                                   sufficient during the compilation of a
#                                   large project such as LLVM.)
#
#                                   Set to "0" to disable the automatic scaling.
#
#   Additional implementation-detail configuration variables exist in
#   'distcc-driver-lib.sh', which need not be altered for normal operation.
#
# HOST SPECIFICATION
#
#   The contents of the DISTCC_AUTO_HOSTS environment variable is the primary
#   configuration option that **MUST** be set by the user prior to using this
#   script.
#   The host list is a whitespace separated list of individual worker host
#   specification entries, which are composed of (usually) a host name and,
#   optionally, the remote server's port number.
#
#   The value is expected to adhere to the following syntax:
#
#     DISTCC_AUTO_HOSTS = AUTO_HOST_SPEC ...
#     AUTO_HOST_SPEC    = TCP_HOST
#     TCP_HOST          = [tcp://]HOSTNAME[:DISTCC_PORT[:STATS_PORT]]
#     HOSTNAME          = ALPHANUMERIC_HOSTNAME
#                       | IPv4_ADDRESS
#                       | IPv6_ADDRESS
#
#   In the above grammar, the meaning of the individual non-terminals are as
#   described below, with examples.
#
#     ALPHANUMERIC_HOSTNAME     A "string" hostname identifying the address of
#                               a worker machine, such as "server" or
#                               "compiler-worker-1.internal.mycompany.org".
#                               The address is resolved naturally and in the
#                               resolv.conf(5) context of the local machine, as
#                               if by the ping(8), wget(1), curl(1) utilities.
#
#     IPv4_ADDRESS              The literal IPv4 address, such as "192.168.1.8".
#
#     IPv6_ADDRESS              The literal IPv6 address, enclosed in square
#                               brackets, such as "[ff06::c3]".
#
#     DISTCC_PORT               The port of the DistCC daemon's TCP job socket.
#                               Defaults to 3632.
#
#     STATS_PORT                The port of the DistCC daemon's statistics
#                               response socket.
#                               Defaults to 3633.
#                               The DistCC server **MUST** support and be
#                               started with the "--stats" and optional
#                               "--stats-port PORT" arguments.
#
# EXIT CODES
#
#   When not indicated otherwise, the script will exit with the exit code of
#   the build invocation command which was passed to 'distcc_build'.
#   The actual build system might have and define various non-zero exit codes
#   for error conditions, which should be looked up from the specific tool's
#   documentation.
#
#   In addition, the main script may generate, prior to the execution of the
#   build tool the following exit codes for error conditions:
#
#      2                        Indicates an issue with the configuration of
#                               the execution environment, such as the emptiness
#                               of a mandatorily set configuration variable, or
#                               the lack of required system tools preventing
#                               normal function.
#
# AUTHOR
#
#    @Whisperity <whisperity-packages@protonmail.com>
#
################################################################################


function distcc_build {
  if [ -n "${DISTCC_HOSTS}" ]; then
    echo "WARNING: Calling distcc_build, but environment variable" \
      "DISTCC_HOSTS is set to something." \
      "The build will **NOT** respect the already set value!" \
      >&2
  fi

  env \
    --unset=DISTCC_HOSTS \
    bash -c "source ./distcc-driver-lib.sh; distcc_driver $*"
}
