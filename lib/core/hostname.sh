#!/bin/bash
# SPDX-License-Identifier: MIT


# Via http://stackoverflow.com/a/36760050.
IPv4_REGEX='((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.){3}(25[0-5]|(2[0-4]|1\d|[1-9]|)\d)'

# Via http://stackoverflow.com/a/17871737.
# It is not a problem that it might match something more, because we just have
# to do a best guess whether the host is an IPv6 one.
IPv6_REGEX='(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))'


function extract_hostname_from_hostspec {
  # Retrieves either an 'ALPHANUMERIC_HOSTNAME', an 'IPv4_ADDRESS', or an
  # 'IPv6_ADDRESS' from the specified partial hostspec line in $1.
  #
  # Returns the hostname as a single string.

  local -r hostspec="$1"

  local hostname
  local match_ipv4
  local match_ipv6
  match_ipv4="$(echo "$hostspec" | grep -Po "$IPv4_REGEX")"
  match_ipv6="$(echo "$hostspec" | grep -Eo "$IPv6_REGEX")"
  if [ -n "$match_ipv4" ]; then
    hostname="$match_ipv4"
    debug "  - Host (IPv4): $hostname"
  elif [ -n "$match_ipv6" ]; then
    hostname="[$match_ipv6]"
    debug "  - Host (IPv6): $hostname"
  else
    hostname="$(echo "$hostspec" | grep -Eo '^([^:]*)')"
    debug "  - Host: $hostname"
  fi

  echo "$hostname"
}


function get_loopback_address {
  # Returns the address of the loopback device 'lo'.

  ip address show lo \
    | grep -Po 'inet \K.*?(?=[/ ])'
}
