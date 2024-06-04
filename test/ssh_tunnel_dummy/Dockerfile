# SPDX-License-Identifier: MIT
FROM ubuntu:20.04

RUN \
  apt-get -y update && \
  apt-get -y install --no-install-recommends \
    netcat \
    openssh-server \
    && \
  mkdir -pv "/run/sshd" && \
  echo "PermitEmptyPasswords yes" >> "/etc/ssh/sshd_config" && \
  echo "PermitRootLogin yes" >> "/etc/ssh/sshd_config" && \
  passwd --delete "root" && \
  true

COPY server.sh /

ENTRYPOINT ["/server.sh"]
