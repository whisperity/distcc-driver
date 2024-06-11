Smart [DistCC](http://distcc.org) driver
========================================

`distcc.sh` &mdash; DistCC remote auto-job script


Summary
-------

Automatically distribute a C/C++ compilation over a DistCC-based cluster with job-count load balancing.


```bash
export DISTCC_AUTO_HOSTS="worker-1 worker-2 worker-3"
source distcc.sh; distcc_build make target1 target2 ...
```



Description
-----------

This script allows remotely building C/C++ projects through a _`distcc`_ cluster.
However, instead of requiring the user to manually configure `DISTCC_HOSTS`, which has a required and non-trivial format (such as specifying the number of jobs to dispatch to a server) and making sure that the called build system is also given an appropriate `--jobs N` parameter, this script automatically balances the available server list, prevents dispatching to servers that do not reply to jobs, and selects the appropriate job count to drive the build with.

It is expected to call this script by prefixing a build command with the wrapper function's name, and specifying the hosts where _`distccd`_ servers are listening.
The called build tool should allow receiving a `-j` parameter, followed by a number.


```bash
DISTCC_AUTO_HOSTS="server-1 server-2" distcc_build make foo
```


In this case, the real call under the hood will expand to something appropriate, such as:


```bash
DISTCC_HOSTS="localhost/8 server-1/16,lzo server-2/8,lzo" make foo -j 32
```



Installation
------------

First, download the contents of this repository and put it to a location where it is out of view.
In this guide, `~/.local/lib/distcc-driver` will be used.
The _DistCC_ client binary, _`distcc`_, should be available in **`PATH`** as well.


```bash
git clone http://github.com/whisperity/DistCC-Driver.git ~/.local/lib/distcc-driver
sudo apt-get -y install --no-install-recommends distcc
```


Then, add the **wrapper script** appropriate for the Shell you are using to your Shell's configuration file.
You might also set the default for [`DISTCC_AUTO_HOSTS`](#configuration-environment-variables) in this file as well.

Loading the wrapper script into your Shell makes it expose the **`distcc_build`** function, which should be used as a prefix to the build system invocation when executing builds.


### [Bash](http://gnu.org/software/bash)

Add the following to the end of `~/.bashrc`:


```bash
source "~/.local/lib/distcc-driver/distcc.sh"

# Example:
export DISTCC_AUTO_HOSTS="worker-1.mycompany.com worker-2.mycompany.com"
```



### [Zsh](http://zsh.org)

Add the following to the end of `~/.zshrc`:


```bash
source "~/.local/lib/distcc-driver/distcc.zsh"

# Example:
export DISTCC_AUTO_HOSTS="worker-1.mycompany.com worker-2.mycompany.com"
```



Configuring C/C++ projects for using `distcc`
---------------------------------------------


> [!TIP]
>
> Compilation with a _DistCC_ cluster works best if you have sufficient storage space to afford [_CCache_](http://ccache.dev) as well.
> [Read further instructions one § later!](#with-ccache)


Unfortunately, just having `distcc` installed will not "magically" make an actual execution of a build, especially when ran through a build system, _use `distcc`_.
The local environment must be configured to take the compilers through _DistCC_'s path.

First, ensure that you have the compilers you intend to use installed on the system.
Then, execute `sudo update-distcc-symlinks`, which will emit symbolic links under `/usr/lib/distcc`, each bearing the name of a compiler.
The easiest way to then configure your build is adding this directory to the _`PATH`_ **prior to** the _"`configure`"_ execution:


```bash
sudo update-distcc-symlinks
export PATH="/usr/lib/distcc:${PATH}"

# When the tools query the path of "gcc" or something else, they will find it in
# the /usr/lib/distcc directory.

# For autotools-based projects:
configure

# For CMake-based projects:
cmake ../path/to/source


# To drive the build after configuring:
DISTCC_AUTO_HOSTS="..." distcc_build make my_target
```


With this approach, the build systems and tools (_`autoconf`_, _`cmake`_, _`make`_, _`ninja`_, etc.) will believe `/usr/lib/distcc/gcc` is **the** compiler (whereas this path actually points to the `distcc` binary, which will do the right thing by dispatching to the compiler!), and, **in general, no other, build-system-specific changes are needed** to successfully compile the project.

Alternatively, you may specify the path of the _"masqueraded"_ compiler manually.
(See _§ MASQUERADE_ in _`man 1 distcc`_ for further details.)


```bash
# For autotools-based projects:
CC="/usr/lib/distcc/gcc" CXX="/usr/lib/distcc/g++" configure

# For CMake-based projects:
cmake ../path/to/source \
  -DCMAKE_C_COMPILER="/usr/lib/distcc/gcc" \
  -DCMAKE_CXX_COMPILER="/usr/lib/distcc/g++"


# To drive the build after configuring:
DISTCC_AUTO_HOSTS="..." distcc_build make my_target
```



### With [`ccache`](http://ccache.dev)

It is **very recommended** to use `distcc` together with [`ccache`](http://ccache.dev) in order to prevent the distribution of compilations of files that did not change to remote workers.

In order to use this feature, **both** _CCache_ and _DistCC_ have to be installed, and, just like in the previous example, the project needs to be configured with the appropriate paths to the compilers.
However, **_CCache_ must take priority** for this combined pipeline to work.

First, ensure that you have the compilers you intend to use installed on the system.
Then, execute `sudo update-ccache-symlinks` **and** `sudo update-distcc-symlinks`, which will emit symbolic links under both `/usr/lib/ccache` and `/usr/lib/distcc`, each bearing the name of a compiler.
The easiest way to then configure your build is adding _CCache_'s directory to the _`PATH`_ **prior to** the _"`configure`"_ execution.
_DistCC_'s directory should be left out of `PATH` in this case.


```bash
sudo apt-get -y install --no-install-recommends ccache distcc
sudo update-ccache-symlinks
sudo update-distcc-symlinks
export PATH="/usr/lib/ccache:${PATH}"

# For autotools-based projects:
configure

# For CMake-based projects:
cmake ../path/to/source


# To drive the build after configuring:
DISTCC_AUTO_HOSTS="..." distcc_build make my_target
```


Similarly to _DistCC_, _CCache_ employs the compiler _masquerading_ feature (see _§ RUN MODES_ in _`man 1 ccache`_), and you may specify the path to the symbolic link of compiler manually:


```bash
# For autotools-based projects:
CC="/usr/lib/ccache/gcc" CXX="/usr/lib/ccache/g++" configure

# For CMake-based projects:
cmake ../path/to/source \
  -DCMAKE_C_COMPILER="/usr/lib/ccache/gcc" \
  -DCMAKE_CXX_COMPILER="/usr/lib/ccache/g++"


# To drive the build after configuring:
DISTCC_AUTO_HOSTS="..." distcc_build make my_target
```



Configuration environment variables
-----------------------------------

| Variable | Explanation | Default |
|:-------- |:------------|:-------:|
| _`DISTCC_HOSTS`_ | The original, official remote worker _"HOST SPECIFICATION"_ as used by DistCC.<br /><br />**⚠️ This variable is _IGNORED_ and _OVERWRITTEN_ by this script!** | _(Inoperative.)_ |
| **`DISTCC_AUTO_HOSTS`** | The list of hosts to check and balance the number of running compilations against. See the exact format below, under [_HOST SPECIFICATION_](#host-specification). Compared to _`DISTCC_HOSTS`_ (**NOT** used by this script!), the number of available job slots on the server need not be specified. | _(Nothing, **must** be specified.)_ |
| `DISTCC_AUTO_COMPILER_MEMORY` | The amount of memory **in MiB** that is expected to be consumed by a **single** compiler process, on average.<br /><br />This value is used to scale the number of jobs dispatched to a worker, if such calculation is applicable. It is usually not necessary to tweak this value prior to encountering performance issues.<br /><br />💡 Set to `0` to _disable_ the automatic scaling. | `1024`<br />(**1 GiB** of memory)<br /><br />💡 This value was empirically verified to be sufficient during the compilation of a large project such as [_LLVM_](http://github.com/llvm/llvm-project). |
| `DISTCC_AUTO_EARLY_LOCAL_JOBS` | The number of jobs to run in parallel **WITHOUT** distributing them to a worker, entirely on the local machine. The local invocation of the compilers will take priority over any remote compilation, which enables not loading the network with jobs if only a few actual compilations would be executed by the build system.<br /><br />It is recommended to set this to a small value, e.g., `2` or `4`, depending on project-specific conditions.<br /><br />ℹ️ This configuration is respected only if **at least one** remote worker is available. | `0`<br />(**NO** local compilations, except for _fallback_ or _failed-job-retry_, as employed by _`distcc`_.) |
| `DISTCC_AUTO_FALLBACK_LOCAL_JOBS` | The number of jobs to run in parallel locally (without distributing them to a worker) in case **NO REMOTE WORKERS** are available at all.<br />Set to `0` to completely **DISABLE** local-only builds and trigger an error exit instead. | _`$(nproc)`_<br />(The number of CPU threads available on the local machine.) |
| `DISTCC_AUTO_PREPROCESSOR_SATURATION_JOBS` | In case there is **AT LEAST ONE** remote worker available, add the specified number of additional jobs that can be spawned in parallel by the build system. These jobs will run the compilation up to the successful preprocessing phase, at which point DistCC will block them until a local worker thread (see _`DISTCC_AUTO_EARLY_LOCAL_JOBS`_) is available to compile them, or a remote machine returns a job and can be sent the next job.<br />This setting allows the local computer to keep a constant supply of pending jobs ready to be dispatched, instead of waiting for an actual compilation (local or remote) to finish before starting the preparation of the next job.<br /><br />💡 Set to `0` to _disable_ local preprocessor saturation.<br /><br />⚠️ As preprocessing is cheap in terms of CPU use and has a barely noticeable overhead on memory, disabling this feature is **NOT RECOMMENDED**, unless the local machine is known to be very weak. It is recommended to keep this feature enabled if the local machine stores source code on a slow-to-access device, e.g., [_HDDs_](http://en.wikipedia.org/wiki/Hard_disk_drive) or [_NFS_](http://en.wikipedia.org/wiki/Network_File_System). | _`$(nproc)`_<br />(The number of CPU threads available on the local machine.) |


Host specification
------------------

The contents of the **`DISTCC_AUTO_HOSTS`** environment variable is the primary configuration option that **MUST** be set by the user prior to using this script.
The host list is a white-space separated list of individual worker host specification entries, which are composed of (usually) a host name and, optionally, the remote server's port number.

The value is expected to adhere to the following syntax:


~~~~
DISTCC_AUTO_HOSTS = AUTO_HOST_SPEC ...
AUTO_HOST_SPEC    = TCP_HOST
                  | SSH_HOST
TCP_HOST          = [tcp://]HOSTNAME[:DISTCC_PORT[:STATS_PORT]]
SSH_HOST          = ssh://[SSH_USER@]HOSTNAME[:SSH_PORT][/DISTCC_PORT[/STATS_PORT]]
HOSTNAME          = ALPHANUMERIC_HOSTNAME
                  | IPv4_ADDRESS
                  | IPv6_ADDRESS
~~~~


In the above grammar, the meaning of the individual non-terminals are as described below, with examples.

| Grammar element | Description | Example |
|:----------------|:------------|:-------:|
| `ALPHANUMERIC_HOSTNAME` | A "string" hostname identifying the address of a worker machine. The address is resolved naturally and in the _`resolv.conf`_ context of the local machine, as if by the _`ping`_, [_`wget`_](http://gnu.org/software/wget), [_`curl`_](http://curl.se) utilities. | `"server"`<br />`"compiler-worker-1.internal.mycompany.org"` |
| `IPv4_ADDRESS` | The literal [_IPv4_](http://en.wikipedia.org/wiki/IPv4) address. | `192.168.1.8` |
| `IPv6_ADDRESS` | The literal [_IPv6_](http://en.wikipedia.org/wiki/IPv6) address, enclosed in _square brackets_ (`[]`). | `[ff06::c3]` |
| `DISTCC_PORT` | The port of the DistCC daemon's TCP job socket. | `3632` |
| `STATS_PORT` | The port of the DistCC daemon's statistics response socket.<br />**⚠️ The _DistCC_ server _MUST_ support and be started with the `--stats` and optional `--stats-port PORT` arguments!** | `3633` |
| `SSH_USER` | The username to use when logging in over [SSH](http://en.wikipedia.org/wiki/Secure_Shell) to the specified server. | _Nothing._<br /><br />The _`ssh`_ client will default it to the `User` set in the SSH configuration file, or falls back to the current user's login name. |
| `SSH_PORT` | The port where the remote server's [SSH](http://en.wikipedia.org/wiki/Secure_Shell) daemon, _`sshd`_, is listening for connections. | _Nothing._<br /><br />The _`ssh`_ client will default it to the `Port` set in the SSH configuration file, or use the global default `22`. |


Exit codes
----------

When not indicated otherwise, the script will exit with the exit code of the build invocation command which was passed to **`distcc_build`**.
(In the above examples, this is the exit code of _`make`_.)
The actual build system might have and define various non-zero exit codes for error conditions, which should be looked up from the specific tool's documentation.

In addition, the main script may generate, prior to the execution of the
build tool, the following exit codes for error conditions:

| Exit code | Explanation |
|:---------:|:------------|
| `96` | Indicates an issue with the configuration of the execution environment, such as the emptiness of a mandatory configuration variable, or the lack of required system tools preventing normal function. |
| `97` | There is not enough system memory (RAM) available on the local computer to run the requested number of local compilations, and no remote workers were available. |


Connecting to servers using [SSH](http://en.wikipedia.org/wiki/Secure_Shell) tunnels
------------------------------------------------------------------------------------

Support for [`SSH_HOST`s](#host-specification) is conditional on having the [_`ssh`_](http://en.wikipedia.org/wiki/Secure_Shell) client installed, and successful execution depends on server-side configuration as well.

In most cases, the remote _`distccd`_ servers are available through the local network and can be used via raw TCP communication to dispatch jobs.
This is the preferred approach, as this allows for doing the work with the least overhead (communication, compression, etc.).

In certain scenarios, however, the "naïve" or "raw" DistCC ports might not be available directly from the client: such is often the case if the servers are in a separate network zone, location, data-centre, than the client machine &emdash; or firewalls could be purposefully or by accident restricting access.
In this case, tunnelling over _`ssh`_ can be a feasible solution to expose the ports on the local machine for _`distcc`_ to consume, without having to reconfigure the network.

_`distcc`_ natively supports an _"SSH Mode"_ and connects to remote servers built-in, but that mode's method is to spawn the **_`distccd`_ server** using the connection, and communicates with the server via a pipe.

**ℹ️ Note** that _SSH tunnelling_, as done by this script, is purposefully **DIFFERENṪ** from _`distcc`_'s aforementioned _"SSH tunnelling"_ mode.

**ℹ️📖 From `man distcc`:**

> For SSH connections, `distccd` must be installed, but should **not** be listening for connections.

This is not always feasible, as it would spawn a server under the name of the user connecting, which may not have the necessary privileges, the running server would not be capable of locking down the total job count across multiple users (i.e., two users spawning two `-j $(nproc)` servers and saturating them fully would overload the remote machine), and might not even have the right set of compilers available.
This is especially the case if the remote servers are [running _`distccd`_ in a containerised environment](http://github.com/whisperity/DistCC-Docker).


### Setting up SSH tunnels

The `distcc-driver` script supports a different approach, which **REQUIRES** a _`distccd`_ (and _`sshd`_) servers to be running on the remote machine, and the existence of the _`ssh`_ client locally.
The remote server must allow the creation of tunnels, especially `AllowTcpForwarding` should be set to `yes`, `all`, or `local`, see _`sshd_config(5)`_.
Naturally, the _`distccd`_ server's "job" (main) and "stats" port must be accessible from the _`sshd`_ server, i.e., if it is running in a containerised namespace, it needs to be exposed thereto.

Specifying an [`SSH_HOST`](#host-specification) will instruct the script to transform the provided `SSH_HOST` internally to a (local machine) `TCP_HOST` that points to a tunnel.
The local ports of the tunnel are selected **randomly**.
This tunnel is **kept alive** throughout the entire execution of the script, and destroyed after.
In case the script fails to establish the tunnel, or the tunnel is created but the remote server does not communicate appropriately, the host is eliminated from the list of potential workers.

Note that from the eventually called _`distcc`_ clients' purview, the tunnelled connections will appear as if compiling on a server running on the local machine (usually with the host IP address `127.0.0.1` or `[::1]`).
Importantly, _`distccmon-text`_ and similar tools will show the _loopback_ address under the remote worker's "name".


### Specifying and customising SSH hosts

The _"hostname"_ part of the [SSH_HOST](#host-specification) might be a trivial hostname `example.com`, or one infixed between a `username@` and/or a `:port` number.
The value is understood as passed to _`ssh`_, similarly to how a "natural" remote terminal connection is made.
As such, the provided hostname component might also be a user-customised `Host` entry's name, see _`ssh_config(5)`_ for details.

The tunnels are created as if by executing:


```bash
ssh \
  -L random-port-1:localhost:DISTCC_PORT \
  -L random-port-2:localhost:STATS_PORT \
  \
  (... additional necessary keep-alive options ...) \
  (... additional internally required detail options ...) \
  (... additional options that disable unneeded features ...) \
  \
  SSH_HOST
```


In certain scenarios, such as if the authentication to the machine is
done via [_PKI_ or identity files](http://en.wikipedia.org/wiki/Public-key_cryptography), and the connection should use a key that is not the default for the **CURRENT** user (e.g., because the entire team is using a dedicated _"CI"_ or _"compiler"_ user on the servers), then this customisation **MUST** be done in the SSH configuration file at `~/.ssh/config`.

For example, you might use an `ssh://worker-1` [host specification](#host-specification) with the following _SSH config_:


```ssh-config
Host worker-1
  HostName compiler-machine-1234.internal.mycompany.com
  User cpp-compiler-team
  IdentityFile ~/.ssh/compiler_team_key
  # ... Additional options such as 'Port' (SSH server port), and other
  # non-randomised 'LocalForward's
```


It is **recommended** to set the server up with key-based authentication instead of requiring the typing in of the remote user's password every time, **and** to run the script in an environment where an _`ssh-agent`_ is available in order to lessen the number of times the potentially password-protected key has to be unlocked over and over again.
