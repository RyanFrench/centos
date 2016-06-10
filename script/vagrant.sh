#!/bin/bash -eux

echo '==> Configuring settings for vagrant'

SSH_USER=${SSH_USERNAME:-vagrant}
SSH_USER_HOME=${SSH_USER_HOME:-/home/${SSH_USER}}

# Packer passes boolean user variables through as '1', but this might change in
# the future, so also check for 'true'.
if [[ "$INSTALL_VAGRANT_KEY" =~ ^(true|yes|on|1|TRUE|YES|ON])$ ]]; then
  # Add vagrant user (if it doesn't already exist)
  if ! id -u $SSH_USER >/dev/null 2>&1; then
      echo '==> Creating ${SSH_USER}'
      /usr/sbin/groupadd $SSH_USER
      /usr/sbin/useradd $SSH_USER -g $SSH_USER -G wheel
      echo '==> Giving ${SSH_USER} sudo powers'
      echo "${SSH_USER}"|passwd --stdin $SSH_USER
      echo "${SSH_USER}        ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers
  fi\

  VAGRANT_INSECURE_KEY=$(eval curl "https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant.pub")

  echo '==> Installing Vagrant SSH key'
  mkdir -pm 700 ${SSH_USER_HOME}/.ssh
  echo "${VAGRANT_INSECURE_KEY}" > $SSH_USER_HOME/.ssh/authorized_keys
  chmod 0600 ${SSH_USER_HOME}/.ssh/authorized_keys
  chown -R ${SSH_USER}:${SSH_USER} ${SSH_USER_HOME}/.ssh
fi
