# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  config.ssh.forward_agent = true
  config.vm.synced_folder "./", "/home/vagrant/flintlock"

  config.vm.network "forwarded_port", guest: 9090, host: 9090
  config.vm.network "forwarded_port", guest: 9091, host: 9091
  config.vm.network "public_network"

  cpus = 2
  memory = 8192
  config.vm.provider :virtualbox do |v|
    # Enable nested virtualisation in VBox
    # v.customize ["modifyvm", :id, "--nested-hw-virt", "on"]

    v.cpus = cpus
    v.memory = memory
  end
  config.vm.provider :libvirt do |v, override|
    # If you want to use a different storage pool.
    # v.storage_pool_name = "vagrant"
    v.cpus = cpus
    v.memory = memory
    override.vm.synced_folder "./", "/home/vagrant/flintlock", type: "nfs"
  end

  config.vm.provision "upgrade-packages", type: "shell", run: "once" do |sh|
    sh.inline = <<~SHELL
      #!/usr/bin/env bash
      set -eux -o pipefail
      #apt update && apt upgrade -y
      apt update
    SHELL
  end

  config.vm.provision "install-basic-packages", type: "shell", run: "once" do |sh|
    sh.inline = <<~SHELL
      #!/usr/bin/env bash
      set -eux -o pipefail
      apt install -y \
        make \
        git \
        gcc \
        curl \
        unzip \
        direnv
    SHELL
  end

  config.vm.provision "install-golang", type: "shell", run: "once" do |sh|
    sh.env = {
      'GO_VERSION': ENV['GO_VERSION'] || "1.23.1",
    }
    sh.inline = <<~SHELL
      #!/usr/bin/env bash
      set -eux -o pipefail
      curl -fsSL "https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz" | tar Cxz /usr/local
      cat >> /etc/environment <<EOF
PATH=/usr/local/go/bin:$PATH
EOF
      source /etc/environment
      cat >> /etc/profile.d/sh.local <<EOF
GOPATH=\\$HOME/go
PATH=\\$GOPATH/bin:\\$PATH
export GOPATH PATH
EOF
    source /etc/profile.d/sh.local
    SHELL
  end

  config.vm.provision "install-kvm", type: "shell", run: "once" do |sh|
    sh.inline = <<~SHELL
      #!/usr/bin/env bash
      set -eux -o pipefail
      apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
      adduser 'vagrant' libvirt
      adduser 'vagrant' kvm
      #setfacl -m u:${USER}:rw /dev/kvm
    SHELL
  end

  config.vm.provision "install-devbox", type: "shell", run: "once" do |sh|
    sh.inline = <<~SHELL
      #!/usr/bin/env bash
      set -eux -o pipefail
      sh <(curl -L https://nixos.org/nix/install) --daemon
      curl -L -o devbox https://releases.jetify.com/devbox 
      mv ./devbox /usr/local/bin
    SHELL
  end
end
