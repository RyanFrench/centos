#!/bin/bash

if [[ ! "$NODEJS" =~ ^(true|yes|on|1|TRUE|YES|ON])$ ]]; then
  exit
fi

SSH_USER=${SSH_USERNAME:-vagrant}
SSH_USER_HOME=${SSH_USER_HOME:-/home/${SSH_USER}}

echo '==> Installing NVM for NodeJS development'

# Run the NVM installer
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.31.1/install.sh | NVM_DIR="${SSH_USER_HOME}/.nvm" PROFILE="${SSH_USER_HOME}/.bashrc" bash
