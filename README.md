Smart [DistCC](http://distcc.org) driver
========================================

`distcc.sh` &emdash; DistCC remote auto-job script


Summary
-------

Automatically distribute a C/C++ compilation over a DistCC-based cluster with job-count load balancing.

    export DISTCC_AUTO_HOSTS="worker-1 worker-2 worker-3"
    source distcc.sh; distcc_build make target1 target2 ...


Description
-----------

This script allows remotely building C/C++ projects through a _distcc(1)_ cluster.
However, instead of requiring the user to manually configure `DISTCC_HOSTS`, which has a required and non-trivial format (such as specifying the number of jobs to dispatch to a server) and making sure that the called build system is also given an appropriate `--jobs N` parameter, this script automatically balances the available server list, prevents dispatching to servers that do not reply to jobs, and selects the appropriate job count to drive the build with.

It is expected to call this script by prefixing a build command with the wrapper function's name, and specifying the hosts where _distccd(1)_ servers are listening.
The called build tool should allow receiving a `-j` parameter, followed by a number.

    DISTCC_AUTO_HOSTS="server-1 server-2" distcc_build make foo

In this case, the real call under the hood will expand to something appropriate, such as:

    DISTCC_HOSTS="localhost/8 server-1/16,lzo server-2/8,lzo" make foo -j 32


Configuration environment variables
-----------------------------------

| Variable                                   | Explanation                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Default                                                                                                                                                      |
|:-------------------------------------------|:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|:------------------------------------------------------------------------------------------------------------------------------------------------------------:|
| _`DISTCC_HOSTS`_                           | The original, official remote worker _"HOST SPECIFICATION"_ as used by DistCC.<br /><br />**⚠️ This variable is _IGNORED_ and _OVERWRITTEN_ by this script!**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | _(Inoperative.)_                                                                                                                                             |
| **`DISTCC_AUTO_HOSTS`**                    | The list of hosts to check and balance the number of running compilations against. See the exact format below, under [_HOST SPECIFICATION_](#host-specification). Compared to _`DISTCC_HOSTS`_ (**NOT** used by this script!), the number of available job slots on the server need not be specified.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | _(Nothing, **must** be specified.)_                                                                                                                          |
| `DISTCC_AUTO_COMPILER_MEMORY`              | The amount of memory **in MiB** that is expected to be consumed by a **single** compiler process, on average.<br /><br />This value is used to scale the number of jobs dispatched to a worker, if such calculation is applicable. It is usually not necessary to tweak this value prior to encountering performance issues.<br /><br />💡 Set to `0` to _disable_ the automatic scaling.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | `1024`<br />(**1 GiB** of memory)<br /><br />💡 This value was empirically verified to be sufficient during the compilation of a large project such as LLVM. |
| `DISTCC_AUTO_EARLY_LOCAL_JOBS`             | The number of jobs to run in parallel **WITHOUT** distributing them to a worker, entirely on the local machine. The local invocation of the compilers will take priority over any remote compilation, which enables not loading the network with jobs if only a few actual compilations would be executed by the build system.<br /><br />It is recommended to set this to a small value, e.g., `2` or `4`, depending on project-specific conditions.<br /><br />ℹ️ This configuration is respected only if **at least one** remote worker is available.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `0`<br />(**NO** local compilations, except for _fallback_ or _failed-job-retry_, as employed by _distcc(1)_.)                                               |
| `DISTCC_AUTO_FALLBACK_LOCAL_JOBS`          | The number of jobs to run in parallel locally (without distributing them to a worker) in case **NO REMOTE WORKERS** are available at all.<br />Set to `0` to completely **DISABLE** local-only builds and trigger an error exit instead.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | _`$(nproc)`_<br />(The number of CPU threads available on the local machine.)                                                                                |
| `DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS` | In case there is **AT LEAST ONE** remote worker available, add the specified number of additional jobs that can be spawned in parallel by the build system. These jobs will run the compilation up to the successful preprocessing phase, at which point DistCC will block them until a local worker thread (see _`DISTCC_AUTO_EARLY_LOCAL_JOBS`_) is available to compile them, or a remote machine returns a job and can be sent the next job.<br />This setting allows the local computer to keep a constant supply of pending jobs ready to be dispatched, instead of waiting for an actual compilation (local or remote) to finish before starting the preparation of the next job.<br /><br />💡 Set to `0` to _disable_ local preprocessor saturation.<br /><br />⚠️ As preprocessing is cheap in terms of CPU use and has a barely noticeable overhead on memory, disabling this feature is **NOT RECOMMENDED**, unless the local machine is known to be very weak. It is recommended to keep this feature enabled if the local machine stores source code on a slow-to-access device, e.g., [_HDDs_](http://en.wikipedia.org/wiki/Hard_disk_drive) or [_NFS_](http://en.wikipedia.org/wiki/Network_File_System). | _`$(nproc)`_<br />(The number of CPU threads available on the local machine.)


Host specification
------------------

The contents of the `DISTCC_AUTO_HOSTS` environment variable is the primary configuration option that **MUST** be set by the user prior to using this script.
The host list is a whitespace separated list of individual worker host specification entries, which are composed of (usually) a host name and, optionally, the remote server's port number.

The value is expected to adhere to the following syntax:

~~~~
DISTCC_AUTO_HOSTS = AUTO_HOST_SPEC ...
AUTO_HOST_SPEC    = TCP_HOST
TCP_HOST          = [tcp://]HOSTNAME[:DISTCC_PORT[:STATS_PORT]]
HOSTNAME          = ALPHANUMERIC_HOSTNAME
                  | IPv4_ADDRESS
                  | IPv6_ADDRESS
~~~~

In the above grammar, the meaning of the individual non-terminals are as described below, with examples.

| Grammar element         | Description                                                                                                                                                                                                                                                            | Example                                                      |
|:------------------------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|:------------------------------------------------------------:|
| `ALPHANUMERIC_HOSTNAME` | A "string" hostname identifying the address of a worker machine. The address is resolved naturally and in the _resolv.conf(5)_ context of the local machine, as if by the _ping(8)_, [_wget(1)_](http://gnu.org/software/wget), [_curl(1)_](http://curl.se) utilities. | `"server"`<br />`"compiler-worker-1.internal.mycompany.org"` |
| `IPv4_ADDRESS`          | The literal [_IPv4_](http://en.wikipedia.org/wiki/IPv4) address.                                                                                                                                                                                                       | `192.168.1.8`                                                |
| `IPv6_ADDRESS`          | The literal [_IPv6_](http://en.wikipedia.org/wiki/IPv6) address, enclosed in _square brackets_ (`[]`).                                                                                                                                                                 | `[ff06::c3]`                                                 |
| `DISTCC_PORT`           | The port of the DistCC daemon's TCP job socket.                                                                                                                                                                                                                        | `3632`                                                       |
| `STATS_PORT`            | The port of the DistCC daemon's statistics response socket.<br />**⚠️ The DistCC server _MUST_ support and be started with the `--stats` and optional `--stats-port PORT` arguments!**                                                                                  | `3633`                                                       |


Exit codes
----------

When not indicated otherwise, the script will exit with the exit code of the build invocation command which was passed to `distcc_build`.
(In the above examples, this is the exit code of `make`.)
The actual build system might have and define various non-zero exit codes for error conditions, which should be looked up from the specific tool's documentation.

In addition, the main script may generate, prior to the execution of the
build tool, the following exit codes for error conditions:

| Exit code | Explanation                                                                                                                                                                                           |
|:---------:|:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `96`      | Indicates an issue with the configuration of the execution environment, such as the emptiness of a mandatory configuration variable, or the lack of required system tools preventing normal function. |
| `97`      | There is not enough system memory (RAM) available on the local computer to run the requested number of local compilations, and no remote workers were available.                                      |
