# SPDX-License-Identifier: MIT
FROM ubuntu:20.04

# CAUTION! Do not **EVER** run this image or use this image for ANYTHING that is
# production-grade.
# This is **ONLY USED FOR A SMALL TEST** as an infrastructure helper!
# Using this image will allow **ANYONE** to take over "root" inside the
# container, as it has no password, which might have
# **CATASTROPHIC CONSEQUENCES** even for your host machine!!!

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
