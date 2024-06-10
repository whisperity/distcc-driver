#!/bin/bash
# SPDX-License-Identifier: MIT
#
################################################################################
### distcc-driver(1)      DistCC remote auto-job script     distcc-driver(1) ###
#
# NAME
#
#   distcc-driver-ssh
#
#
# SUMMARY
#
#   Handles connecting to and tunnelling DistCC servers that are available behind
#   an SSH connection.
#
#   Note that this is purposefully **DIFFERENT** from distcc(1)'s own
#   "SSH tunnelling" mode, as "DistCC-over-SSH" would mean that it is distcc(1)
#   that initiates the connection **AND** starts distccd(1) during the remote
#   compilation session.
#   Such a workflow is usually incompatible with distccd(1) servers that are
#   pre-initialised, especially if they are running in a containerised context.
#
#
# REASONS FOR SSH MODE
#
#   In most cases, the remote distccd(1) servers are available through the local
#   network and can be used via raw TCP communication to dispatch jobs.
#   This is the preferred approach, as this allows for doing the work with the
#   least overhead (communication, compression, etc.).
#
#   In certain scenarios, however, the "naive" or "raw" DistCC ports might not
#   be available directly from the client: such is often the case if the servers
#   are in a separate network zone, location, data-centre, than the client
#   machine - or firewalls could be purposefully or by accident restricting
#   access.
#   In this case, tunnelling over ssh(1) can be a feasible solution to expose
#   the ports on the local machine for distcc(1) to consume, without having to
#   reconfigure the network.
#
#   distcc(1) natively supports an "SSH Mode" and connects to remote servers
#   built-in, but that mode's method is to spawn the distccd(1) **server** using
#   the connection, and communicates with the server via a pipe.
#
#   Note from "man distcc":
#
#     > For SSH connections, distccd must be installed, but should **not** be
#     > listening for connections.
#
#   This is not always feasible, as it would spawn a server under the name of
#   the user connecting, which may not have the necessary privileges, the
#   running server would not be capable of locking down the total job count
#   across multiple users (i.e., two users spawning two "-j $(nproc)" servers
#   and saturating them fully would overload the remote machine), and might not
#   even have the right set of compilers available.
#   This is especially the case if the remote servers are running distccd(1) in
#   a containerised environment.
#
#
# SETTING UP SSH TUNNELS
#
#   Instead, the distcc-driver script supports a different approach, which
#   **REQUIRES** a distccd(1) (and sshd(8)) servers to be running on the remote
#   machine, and the existence of the ssh(1) client locally.
#   The remote server must allow the creation of tunnels, especially
#   'AllowTcpForwarding' should be set to 'yes', 'all', or 'local',
#   see sshd_config(5).
#   Naturally, the distccd(1) server's "job" (main) and "stats" port must be
#   accessible from the sshd(8) server, i.e., if it is running in a
#   containerised namespace, it needs to be exposed thereto.
#
#   Specifying an SSH_HOST (see the main documentation in 'distcc.sh' for
#   details) will instruct the script to transform the provided SSH_HOST
#   internally to a (local machine) TCP_HOST that points to a tunnel.
#   The local ports of the tunnel are selected **randomly**.
#   This tunnel is **kept alive** throughout the entire execution of the script,
#   and destroyed after.
#   In case the script fails to establish the tunnel, or the tunnel is created
#   but the remote server does not communicate appropriately, the host is
#   eliminated from the list of potential workers.
#
#   Note that from the eventually called distcc(1) clients' purview, the
#   tunnelled connections will appear as if compiling on a server running on the
#   local machine (usually with the host IP address "127.0.0.1" or "[::1]").
#   Importantly, distccmon-text(1) and similar tools will show the loopback
#   address under the remote worker's "name".
#
#
# SPECIFYING AND CUSTOMISING SSH HOSTS
#
#   As a summary, please see the grammar in the main documentation
#   of 'distcc.sh'.
#
#   The hostname part of the SSH_HOST might be a trivial hostname "example.com",
#   or one infixed between a "username@" and/or a ":port" number.
#   The value is understood as passed to ssh(1), similarly to how a "natural"
#   remote terminal connection is made.
#   As such, the provided hostname component might also be a user-customised
#   "Host" entry's name, see ssh_config(5) for details.
#
#   The tunnels are created as if by executing:
#
#     ssh \
#       -L random-port-1:localhost:DISTCC_PORT \
#       -L random-port-2:localhost:STATS_PORT \
#       [... additional necessary keep-alive options ...] \
#       [... additional internally required detail options ...] \
#       [... additional options that disable unneeded features ...] \
#       SSH_HOST
#
#   In certain scenarios, such as if the authentication to the machine is
#   done via PKI or identity files, and the connection should use a key that is
#   not the default for the **CURRENT** user (e.g., because the entire team is
#   using a dedicated "CI" or "compiler" user on the servers), then this
#   customisation **MUST** be done in the SSH configuration file at
#   '~/.ssh/config'.
#
#   For example, you might use an "ssh://worker-1" HOST SPECIFICATION with the
#   following SSH config:
#
#     Host worker-1
#       HostName compiler-machine-1234.internal.mycompany.com
#       User cpp-compiler-team
#       IdentityFile ~/.ssh/compiler_team_key
#       # ... Additional options such as 'Port' (SSH server port), and other
#       # non-randomised 'LocalForward's
#
#   It is recommended to set the server up with key-based authentication instead
#   of requiring the typing in of the remote user's password every time, and
#   to run the script in an environment where an ssh-agent(1) is available in
#   order to lessen the number of times the potentially password-protected key
#   has to be unlocked over and over again.
#
#
# AUTHOR
#
#    @Whisperity <whisperity-packages@protonmail.com>
#
################################################################################


_DCCSH_HAS_SSH_SUPPORT=1
_DCCSH_SSH_RETRY_LIMIT=5


function check_commands_ssh {
  _check_command cat
  _check_command env
  _check_command grep
  _check_command head
  _check_command kill
  _check_command pgrep
  _check_command sed
  _check_command sleep
  _check_command ssh
  _check_command tail

  if [ "$_DCCSH_HAS_MISSING_TOOLS" -ne 0 ]; then
    _DCCSH_HAS_SSH_SUPPORT=0
  fi
}


function parse_ssh_hostspec {
  # Parses an AUTO_HOST_SPEC which is according to the SSH_HOST grammar.
  # Returns the single '/'-separated split specification fields:
  # "PROTOCOL/[USERNAME@]HOSTNAME[:PORT]/

  local hostspec="$1"
  local -r original_hostspec="$hostspec"

  local ssh_full_host
  ssh_full_host="$(echo "$hostspec" | grep -Eo '^([^/]*)')"

  local username
  local match_username
  match_username="$(echo "$ssh_full_host" | grep -Eo '^([^@]*)@' \
    | sed 's/@$//')"
  if [ -n "$match_username" ]; then
    username="$match_username"
    hostspec="${hostspec/"$username@"/}"
  fi

  local hostname
  hostname="$(echo "$hostspec" | grep -Eo '^([^/]*)')"
  hostname="$(get_hostname_from_hostspec "$hostname")"
  hostspec="${hostspec/"$hostname"/}"

  if [ -n "$username" ]; then
    debug "  - User: $username"
  fi

  local -i ssh_port
  local match_port
  match_port="$(echo "$hostspec" | grep -Eo '^:[0-9]{1,5}' | sed 's/^://')"
  if [ -n "$match_port" ]; then
    # If the match-port matched with ':' as the prefix, it MUST be the
    # "SSH port", as per the grammar definition for SSH_HOST.
    ssh_port="$match_port"
    hostspec="${hostspec/":$ssh_port"/}"
    debug "  - SSH port: $ssh_port"
  fi

  local -i job_port="$_DCCSH_DEFAULT_DISTCC_PORT"
  local -i stat_port="$_DCCSH_DEFAULT_STATS_PORT"
  match_port="$(echo "$hostspec" | grep -Eo '^/[0-9]{1,5}' | sed 's/^\///')"
  if [ -n "$match_port" ]; then
    # If the match-port matched **once** with '/' as the prefix, it MUST be the
    # "job port", as per the grammar definition for SSH_HOST.
    job_port="$match_port"
    hostspec="${hostspec/"/$job_port"/}"
    debug "  - Port: $job_port"
  fi
  match_port="$(echo "$hostspec" | grep -Eo '^/[0-9]{1,5}' | sed 's/^\///')"
  if [ -n "$match_port" ]; then
    # If the match-port matched **twice** with '/' as the prefix, the second
    # match MUST be the "stats port", as per the grammar definition for
    # SSH_HOST.
    stat_port="$match_port"
    hostspec="${hostspec/"/$stat_port"/}"
    debug "  - Stat: $stat_port"
  fi

  # After parsing, the hostspec should have emptied.
  if [ -n "$hostspec" ]; then
    log "WARNING" "Parsing of malformed DISTCC_AUTO_HOSTS entry" \
      "\"$original_hostspec\" did not conclude cleanly, and \"$hostspec\"" \
      "was ignored!"
  fi

  # Return value.
  array '/' "ssh" "$ssh_full_host" "$job_port" "$stat_port"
}


function random_port_number {
  # Returns a random port in the non-superuser range.
  # It is not checked whether the port is valid for binding by a server.

  # Return value.
  echo "$(( ( (RANDOM << 15) | RANDOM ) % (65536 - 1024) + 1024 ))"
}


function ssh_tunnel_pidfile {
  # Returns the location where SSH tunnel information should be written.

  echo "$DCCSH_TEMP/ssh-tunnel-pids.txt"
}


function transform_ssh_hostspec {
  # Creates an SSH tunnel based on the given host specification ($1) and returns
  # the established tunnel's client-side end as a TCP host specification.

  local -r hostspec="$1"
  local -a hostspec_fields
  IFS='/' read -ra hostspec_fields <<< "$hostspec"

  local -r protocol="${hostspec_fields[0]}"
  if [ "$protocol" != "ssh" ]; then
    return 1
  fi

  local -a ssh_client_args=()

  # SSH Host is formatted either "username@host" or "username@host:port".
  # OpenSSH client accepts either "username@host -p port" or
  # "ssh://username@host:port".
  local -r ssh_host="${hostspec_fields[1]}"

  local -ri job_port_on_server="${hostspec_fields[2]}"
  local -ri stat_port_on_server="${hostspec_fields[3]}"


  # Disable most of the interactivity over the SSH connection - the user will
  # not be here to do anything, confirm anything, unlock anything, etc., anyway.
  ssh_client_args+=(
    "-fnN"
    "-o" "AddKeysToAgent=yes"
    "-o" "CheckHostIP=no"
    "-o" "ConnectTimeout=10"
    "-o" "GlobalKnownHostsFile=/dev/null"
    "-o" "LogLevel=ERROR"
    "-o" "PasswordAuthentication=yes"
    "-o" "PubkeyAuthentication=yes"
    "-o" "ServerAliveInterval=60"
    "-o" "StrictHostKeyChecking=off"
    "-o" "TCPKeepAlive=yes"
    "-o" "UserKnownHostsFile=/dev/null"
  )

  # Ensure that the failure to bind the tunnels kills the connection.
  ssh_client_args+=("-o" "ExitOnForwardFailure=yes")

  # Disable some common forwarding options that users MIGHT have set up for the
  # host in their 'ssh_config' if they also use the host as an interactive
  # system.
  ssh_client_args+=(
    "-ax"
    "-o" "ForwardAgent=no"
    "-o" "ForwardX11=no"
    "-o" "ForwardX11Trusted=no"
    "-T"
    "-o" "RequestTTY=no"
  )

  # GZip Compression is known to be intractable on fast enough networks as it
  # introduces additional overhead that is not necessary in most settings,
  # especially in our case with text-only background communication.
  #
  # The distcc(1) client itself will use its own LZO compression for the
  # communication of the source and objects, anyway.
  ssh_client_args+=("-o" "Compression=no")

  local -i retries=1
  while [ "$retries" -le "$_DCCSH_SSH_RETRY_LIMIT" ]; do
    local -a ssh_client_args_with_ports=("${ssh_client_args[@]}")

    # Set up a random local port to forward connections to the remote server.
    local -i job_port_local
    job_port_local="$(random_port_number)"
    local -i stat_port_local="$(( job_port_local + 1 ))"

    ssh_client_args_with_ports+=(
      "-L"
      "$(loopback_address):$job_port_local:localhost:$job_port_on_server"

      "-L"
      "$(loopback_address):$stat_port_local:localhost:$stat_port_on_server"
    )
    ssh_client_args_with_ports+=("ssh://$ssh_host")

    # Attempt the connection.
    debug "Executing SSH tunnel via command:" \
      "ssh ${ssh_client_args_with_ports[*]} ..."
    env \
        ssh \
          "${ssh_client_args_with_ports[@]}"

    local -i ssh_pid=0
    ssh_pid="$(pgrep -f \
      "ssh.*-L.*$job_port_local.*$job_port_on_server.*-L.*$stat_port_local.*$stat_port_on_server.*$ssh_host" \
      )"

    if ! ps "$ssh_pid" &>/dev/null; then
      log "WARNING" "($retries/$_DCCSH_SSH_RETRY_LIMIT)" \
        "Failed to establish SSH connection with tunnels to \"$hostspec\"!"
    else
      debug "SSH connection via process #$ssh_pid established to: \"$hostspec\""
      break
    fi

    retries+=1
  done

  if [ "$retries" -gt "$_DCCSH_SSH_RETRY_LIMIT" ]; then
    log "ERROR" "Failed to establish SSH connection with tunnels to" \
      "\"$hostspec\" after $_DCCSH_SSH_RETRY_LIMIT retries!"
    return 2
  fi

  local -r tcp_hostspec="$(array '/' \
    "tcp" "$(loopback_address)" "$job_port_local" "$stat_port_local" \
    )"

  cat <<EOF >> "$(ssh_tunnel_pidfile)"
# SSH: $ssh_host
# TCP: $(loopback_address)
# D_Tunnel: $job_port_local -> $job_port_on_server
# S_Tunnel: $stat_port_local -> $stat_port_on_server
# PID: $ssh_pid
$hostspec=$tcp_hostspec=$ssh_pid

EOF

  # Return value.
  echo "$tcp_hostspec"
}


function cleanup_ssh {
  # Kills ssh(1) processes created by transform_ssh_hostspec().

  if [ ! -f "$(ssh_tunnel_pidfile)" ]; then
    return
  fi

  local -a ssh_tunnels=()
  mapfile -t ssh_tunnels < \
    <(grep -v '^#\|^$' "$(ssh_tunnel_pidfile)" \
      | head -c -1)

  for tunnel in "${ssh_tunnels[@]}"; do
    local -a tunnel_fields
    IFS='=' read -ra tunnel_fields <<< "$tunnel"

    local ssh_hostspec="${tunnel_fields[0]}"
    local -i ssh_pid="${tunnel_fields[2]}"
    debug "Closing SSH tunnel of host: $ssh_hostspec ..."

    # Waits until the given PID exited.
    # Fixes the issue of not being able to wait on a "random" PID that is
    # not in fact a child of the current shell, because SSH backgrounded itself.
    tail --quiet -f "/dev/null" --pid "$ssh_pid" &
    local -i tail_pid=$!

    debug "Executing command: kill $ssh_pid"
    kill "$ssh_pid"

    # Wait for the SSH process to terminate, at which point tail will return.
    # Tail **IS** a child of the current shell, so this wait is legal.
    wait "$tail_pid"
  done

  if [ -z "$DCCSH_DEBUG" ]; then
    rm "$(ssh_tunnel_pidfile)"
  fi
}
