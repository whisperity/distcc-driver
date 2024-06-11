#!/bin/bash
# SPDX-License-Identifier: MIT


FAKE_DISTCC_RESPONSE="$(cat <<EOF
HTTP/1.1 200 OK
Content-Type: text/plain
Connection: close

argv /distccd
<distccstats>
dcc_tcp_accept 0
dcc_rej_bad_req 0
dcc_rej_overload 0
dcc_compile_ok 0
dcc_compile_error 0
dcc_compile_timeout 0
dcc_cli_disconnect 0
dcc_other 0
dcc_longest_job none
dcc_longest_job_compiler none
dcc_longest_job_time_msecs -1
dcc_max_kids $(date +"%Y%m%d")
dcc_avg_kids1 0
dcc_avg_kids2 0
dcc_avg_kids3 0
dcc_current_load 0
dcc_load1 0
dcc_load2 0
dcc_load3 0
dcc_num_compiles1 0
dcc_num_compiles2 0
dcc_num_compiles3 0
dcc_num_procstate_D 0
dcc_max_RSS 0
dcc_max_RSS_name (none)
dcc_io_rate 0
dcc_free_space 0 MB
</distccstats>
EOF
)"


echo "$(hostname): Starting sshd ..." >&2
eval "$(which sshd)" -p 2222


raw_server() {
  while true; do
    sleep 1

    echo "$(hostname): Starting raw \"Hello, World!\" server ..." >&2
    echo "\"Hello, World!\" from: $(hostname)" \
      | netcat -Nl 6362 \
      &

    wait $!
    echo "$(hostname): Raw \"Hello, World!\" server exited!" >&2
  done
}


fake_distcc_stats_server() {
  while true; do
    sleep 1

    echo "$(hostname): Starting fake DistCC stat server ..." >&2
    echo "$FAKE_DISTCC_RESPONSE" \
      | netcat -Nl 6363 \
      &

    wait $!
    echo "$(hostname): Fake DistCC stat server exited!" >&2
  done
}


while true; do
  echo "$(hostname): Starting webservers ..." >&2
  fake_distcc_stats_server &
  p1=$!
  raw_server &
  p2=$!

  wait $p1 $p2
done

