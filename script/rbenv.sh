#!/bin/bash

if [[ ! "$RUBY" =~ ^(true|yes|on|1|TRUE|YES|ON])$ ]]; then
  exit
fi

SSH_USER=${SSH_USERNAME:-vagrant}
SSH_USER_HOME=${SSH_USER_HOME:-/home/${SSH_USER}}

echo '==> Installing RBENV for Ruby development'

# Install dependencies for building ruby
yum install -y openssl-devel readline-devel zlib-devel gcc git

# Clone the repository
su -c "git clone https://github.com/rbenv/rbenv.git ${SSH_USER_HOME}/.rbenv" ${SSH_USER}

# Try to compile the dynamic bash extension
cd ${SSH_USER_HOME}/.rbenv && src/configure && make -C src

# Add rbenv to the vagrant users PATH
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ${SSH_USER_HOME}/.bashrc

# Install ruby-build
git clone https://github.com/rbenv/ruby-build.git ${SSH_USER_HOME}/.rbenv/plugins/ruby-build

# Initialize rbenv on login
echo 'eval "$(rbenv init -)"' >> ${SSH_USER_HOME}/.bashrc
