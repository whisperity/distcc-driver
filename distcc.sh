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
#
# SUMMARY
#
#   Automatically distribute a C/C++ compilation over a DistCC-based cluster
#   with job-count load balancing.
#
#   export DISTCC_AUTO_HOSTS="worker-1 worker-2 worker-3"
#   source distcc.sh; distcc_build make target1 target2...
#
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
#   wrapper function's name, and specifying the hosts where distccd(1) servers
#   are listening.
#   The called build tool should allow receiving a "-j" parameter, followed by
#   a number.
#
#     DISTCC_AUTO_HOSTS="server-1 server-2" distcc_build make foo
#
#   In this case, the real call under the hood will expand to something
#   appropriate, such as:
#
#     DISTCC_HOSTS="localhost/8 server-1/16,lzo server-2/8,lzo" make foo -j 32
#
#
# CONFIGURING C/C++ PROJECTS FOR USING DISTCC
#
#   NOTE:
#
#     Compilation with a DistCC cluster works best if you have sufficient
#     stroage space to afford ccache(1) as well.
#     Read "CONFIGURING C/C++ PROJECTS FOR USING DISTCC (WITH CCACHE)" instead,
#     if applicable!
#
#  Unfortunately, just having distcc(1) installed will not "magically" make an
#  actual execution of a build, especially when ran through a build system, use
#  distcc(1) under the hood.
#  The local environment must be configured to take the compilers **THROUGH**
#  distcc's path.
#
#  This can be achieved by, after installing DistCC, executing
#  'update-distcc-symlinks' as root.
#  That tool will emit symbolic links under /usr/lib/distcc, each bearing the
#  name of a compiler.
#  The easiest way to configure your build is adding this directory to 'PATH'
#  prior to the execution of 'configure' or a similar tool.
#
#    sudo update-distcc-symlinks
#    export PATH="/usr/lib/distcc:${PATH}"
#    configure
#    # Or
#    cmake ../path/to/source
#
#    DISTCC_AUTO_HOSTS="..." distcc_build make my_target
#
#  With this approach, the build systems and tools (autoconf(1), cmake(1),
#  make(1), ninja(1))  will believe '/usr/lib/distcc/gcc' is **THE** compiler
#  (whereas this path actually points to the distcc(1) binary, which will do
#  the right thing by dispatching to the compiler!), and, in general, no other,
#  build-system-specific changes are needed to successfully compile the project.
#
#  Alternatively, you may specify the path of the "masqueraded" compilers
#  manually.
#  (See "MASQUERADE" in distcc(1) for further details.)
#
#    CC="/usr/lib/distcc/gcc" CXX="/usr/lib/distcc/g++" configure
#    # Or:
#    cmake ../path/to/source \
#      -DCMAKE_C_COMPILER="/usr/lib/distcc/gcc" \
#      -DCMAKE_CXX_COMPILER="/usr/lib/distcc/g++"
#
#
# CONFIGURING C/C++ PROJECTS FOR USING DISTCC (WITH CCACHE)"
#
#   It is **VERY RECOMMENDED** to use distcc(1) together with ccache(1) in order
#   to prevent the distribution of compilations of files that did not change to
#   remote workers.
#
#   In order to use this feature, both ccache(1) and distcc(1) have to be
#   installed, and, just like in the example in
#   "CONFIGURING C/C++ PROJECTS FOR USING DISTCC", the project needs to be
#   configured with the appropriate paths to the compilers.
#   However, ccache(1)'s execution **MUST** take priority for the combined
#   pipeline to work.
#
#  This can be achieved by, after installing CCache and DistCC, executing
#  'update-ccache-symlinks' **AND*** 'update-distcc-symlinks' as root.
#  These tools will emit symbolic links under /usr/lib/ccache and
#  /usr/lib/distcc, each bearing the name of a compiler.
#  The easiest way to configure your build is adding **CCACHE'S** directory to
#  'PATH' prior to the execution of 'configure' or a similar tool.
#
#    sudo update-ccache-symlinks
#    sudo update-distcc-symlinks
#    export PATH="/usr/lib/ccache:${PATH}"
#    configure
#    # Or
#    cmake ../path/to/source
#
#    DISTCC_AUTO_HOSTS="..." distcc_build make my_target
#
#  Alternatively, as similarly to distcc(1)'s MASQUERADE facilities, you may
#  specify the path of the ccache(1)-"masqueraded" compilers manually.
#  (See "RUN MODES" in ccache(1) for further details.)
#
#    CC="/usr/lib/ccache/gcc" CXX="/usr/lib/ccache/g++" configure
#    # Or:
#    cmake ../path/to/source \
#      -DCMAKE_C_COMPILER="/usr/lib/ccache/gcc" \
#      -DCMAKE_CXX_COMPILER="/usr/lib/ccache/g++"
#
#
# CONFIGURATION ENVIRONMENT VARIABLES
#
#     DISTCC_HOSTS
#
#       The original, official remote worker "HOST SPECIFICATION" used by
#       DistCC.
#       This variable is **IGNORED** and **OVERWRITTEN** this script!
#
#     DISTCC_AUTO_HOSTS
#
#       The list of hosts to check and balance the number of running
#       compilations against.
#       See the exact format below, under 'HOST SPECIFICATION'.
#       Compared to `DISTCC_HOSTS` (**NOT** used by this script!), the number
#       of available job slots on the server need not be specified.
#
#     DISTCC_AUTO_EARLY_LOCAL_JOBS
#
#       The number of jobs to run in parallel **WITHOUT** distributing them to
#       a worker, entirely on the local machine.
#       The local invocation of the compilers will take priority over any remote
#       compilation, which enables not loading the network with jobs if only a
#       few actual compilations would be executed by the build system.
#
#       It is recommended to set this to a small value, e.g., "2" or "4",
#       depending on project-specific conditions.
#
#       Defaults to "0", which results in **NO** local compilations (except for
#       the fallback or failed-job-retry as employed by distcc(1)) in case
#       **AT LEAST ONE** remote server is available.
#
#     DISTCC_AUTO_FALLBACK_LOCAL_JOBS
#
#       The number of jobs to run in parallel locally (without distributing
#       them to a worker) in case **NO REMOTE WORKERS** are available at all.
#
#       Set to "0" to completely **DISABLE** local-only builds and trigger an
#       error exit instead.
#
#       Defaults to "$(nproc)", the number of CPU threads available on
#       the machine.
#
#     DISTCC_AUTO_COMPILER_MEMORY
#
#       The amount of memory **in MiB** that is expected to be consumed by a
#       **single** compiler process, on average.
#       This value is used to scale the number of jobs dispatched to a worker,
#       if such calculation is applicable.
#       It is usually not necessary to tweak this value prior to encountering
#       performance issues.
#
#       Defaults to a reasonably large value of "1024", corresponding to 1 GiB
#       of memory.
#       (This value was empirically verified to be sufficient during the
#       compilation of a large project such as LLVM.)
#
#       Set to "0" to disable the automatic scaling.
#
#     DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS
#
#       In case there is **AT LEAST ONE** remote worker available, add the
#       specified number of additional jobs that can be spawned in parallel by
#       the build system.
#       These jobs will run the compilation up to the successful preprocessing
#       phase, at which point DistCC will block them until a local worker thread
#       (see DISTCC_AUTO_EARLY_LOCAL_JOBS) is available to compile them, or a
#       remote machine returns a job and can be sent the next job.
#
#       This setting allows the local computer to keep a constant supply of
#       pending jobs ready to be dispatched, instead of waiting for an actual
#       compilation (local or remote) to finish before starting the preparation
#       of the next job.
#
#       Set to "0" to completely **DISABLE** local preprocessor saturation.
#       As preprocessing is cheap in terms of CPU use and has a barely
#       noticeable overhead on memory, doing so is **NOT RECOMMENDED**, unless
#       the local machine is known to be very weak.
#
#       It is recommended to keep this feature enabled if the local machine
#       stores souce code on a slow-to-access device (e.g., HDD or NFS).
#
#       Defaults to "$(nproc)", the number of CPU threads available on
#       the machine.
#
#
#   Additional implementation-detail configuration variables exist in
#   'driver.sh', which need not be altered for normal operation.
#
#
# HOST SPECIFICATION
#
#   The contents of the DISTCC_AUTO_HOSTS environment variable is the primary
#   configuration option that **MUST** be set by the user prior to using this
#   script.
#   The host list is a white-space separated list of individual worker host
#   specification entries, which are composed of (usually) a host name and,
#   optionally, the remote server's port number.
#
#   The value is expected to adhere to the following syntax:
#
#     DISTCC_AUTO_HOSTS = AUTO_HOST_SPEC ...
#     AUTO_HOST_SPEC    = TCP_HOST
#                       | SSH_HOST
#     TCP_HOST          = [tcp://]HOSTNAME[:DISTCC_PORT[:STATS_PORT]]
#     SSH_HOST          = ssh://[SSH_USER@]HOSTNAME[:SSH_PORT][/DISTCC_PORT[/STATS_PORT]]
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
#     SSH_USER                  The username to use when logging in over SSH to
#                               the specified server.
#                               Defaults to nothing, in which case ssh(1) client
#                               will default it to the "User" set in the SSH
#                               configuration file, or with the current
#                               user's login name.
#
#     SSH_PORT                  The port where the remote server's SSH daemon,
#                               sshd(8), is listening for connections.
#                               Defaults to nothing, in which case the ssh(1)
#                               client will default it to the "Port" set in the
#                               SSH configuration file, or use the global
#                               default 22.
#
#   Support for SSH_HOSTs is conditional on having the ssh(1) client installed,
#   and successful execution depends on server-side configuration as well.
#   Please see the documentation in 'lib/ssh.sh' for details.
#
#
# EXIT CODES
#
#   When not indicated otherwise, the script will exit with the exit code of
#   the build invocation command which was passed to 'distcc_build'.
#   (In the above examples, this is the exit code of "make".)
#   The actual build system might have and define various non-zero exit codes
#   for error conditions, which should be looked up from the specific tool's
#   documentation.
#
#   In addition, the main script may generate, prior to the execution of the
#   build tool, the following exit codes for error conditions:
#
#      96
#
#          Indicates an issue with the configuration of the execution
#          environment, such as the emptiness of a mandatory configuration
#          variable, or the lack of required system tools preventing normal
#          function.
#
#      97
#
#          There is not enough system memory (RAM) available on the local
#          computer to run the requested number of local compilations, and no
#          remote workers were available.
#
#
# AUTHOR
#
#    @Whisperity <whisperity-packages@protonmail.com>
#
################################################################################


function _distcc_auto_lib_path {
  # Determines the location where the currently loaded script is.
  # Needed to accurately source the actual "library" code when distcc_build is
  # called.
  #
  # Via http://stackoverflow.com/a/246128.

  local file="${BASH_SOURCE[0]}"
  local dir
  while [ -L "$file" ]; do
    dir=$( cd -P "$( dirname "$file" )" >/dev/null 2>&1 && pwd )
    file=$(readlink "$file")
    [[ "$file" != /* ]] && file=$dir/$file
  done
  dir=$( cd -P "$( dirname "$file" )" >/dev/null 2>&1 && pwd )

  # Return value.
  echo "$file"
}


_DCCSH_SCRIPT_PATH="$(dirname -- "$(readlink -f "$(_distcc_auto_lib_path)")")"


function distcc_build {
  if [ -n "${DISTCC_HOSTS}" ]; then
    echo "WARNING: Calling distcc_build, but environment variable" \
      "DISTCC_HOSTS is set to something." \
      "The build will **NOT** respect the already set value!" \
      >&2
  fi

  env \
    --unset=DISTCC_HOSTS \
    bash -c "source ${_DCCSH_SCRIPT_PATH}/lib/driver.sh; distcc_driver $*"
}
