#!/bin/bash
# provision-droplet.sh - Run this on a fresh DO Ubuntu 24.04 droplet
# This replicates the Vagrantfile provisioning for production use

set -euo pipefail

echo "🚀 Starting DigitalOcean droplet provisioning..."

# Equivalent to Vagrantfile's "upgrade-packages" provision
echo "📦 Updating packages..."
sudo apt update
# Note: We skip apt upgrade to keep provisioning fast, but you can add it:
# sudo apt upgrade -y

# Equivalent to Vagrantfile's "install-basic-packages" provision  
echo "🔧 Installing basic packages..."
sudo apt install -y \
    make \
    git \
    gcc \
    curl \
    unzip \
    direnv

# Equivalent to Vagrantfile's "install-golang" provision
echo "🐹 Installing Go..."
GO_VERSION="1.23.1"
curl -fsSL "https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz" | sudo tar Cxz /usr/local

# Set up Go environment (equivalent to Vagrantfile's environment setup)
echo 'PATH=/usr/local/go/bin:$PATH' | sudo tee -a /etc/environment
echo 'export GOPATH=$HOME/go' >> ~/.profile
echo 'export PATH=$GOPATH/bin:$PATH' >> ~/.profile

# Also set for current session
export PATH=/usr/local/go/bin:$PATH
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$PATH

# Equivalent to Vagrantfile's "install-kvm" provision
# THIS IS THE KEY DIFFERENCE - this actually works on bare metal!
echo "🖥️  Installing KVM and virtualization tools..."
sudo apt install -y qemu-system-x86 libvirt-daemon-system libvirt-clients bridge-utils virt-manager

# Add current user to virtualization groups
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

# Enable and start libvirt service (this works on real VMs, not containers)
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# Equivalent to Vagrantfile's "install-devbox" provision
echo "📦 Installing Nix and Devbox..."
# Install Nix (non-interactive)
curl -L https://nixos.org/nix/install | sh -s -- --daemon

# Install Devbox
curl -L -o /tmp/devbox https://releases.jetify.com/devbox
sudo mv /tmp/devbox /usr/local/bin/devbox
sudo chmod +x /usr/local/bin/devbox

# Additional setup for your Firecracker use case
echo "🔥 Installing Firecracker..."
FIRECRACKER_VERSION="v1.7.0"
wget "https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-x86_64.tgz"
tar -xzf firecracker-${FIRECRACKER_VERSION}-x86_64.tgz
sudo mv release-${FIRECRACKER_VERSION}-x86_64/firecracker-${FIRECRACKER_VERSION}-x86_64 /usr/local/bin/firecracker
sudo chmod +x /usr/local/bin/firecracker
rm -rf firecracker-${FIRECRACKER_VERSION}-x86_64.tgz release-${FIRECRACKER_VERSION}-x86_64

echo "📦 Installing containerd..."
sudo apt install -y containerd

# Set up firewall (DigitalOcean best practice)
echo "🔒 Setting up basic firewall..."
sudo ufw allow ssh
sudo ufw allow 9090  # Equivalent to Vagrantfile port forwarding
sudo ufw allow 9091  # Equivalent to Vagrantfile port forwarding
sudo ufw --force enable

# Create project directory (equivalent to Vagrantfile synced folder)
echo "📁 Creating project directory..."
mkdir -p $HOME/flintlock

# Set proper permissions
sudo chown -R $USER:$USER $HOME/flintlock

echo "✅ Provisioning complete!"
echo "🔄 You should reboot the droplet to ensure all group memberships take effect:"
echo "   sudo reboot"
echo ""
echo "📍 After reboot, verify everything works:"
echo "   - Go: go version"
echo "   - KVM: ls -la /dev/kvm"
echo "   - Firecracker: firecracker --version"
echo "   - Groups: groups (should include kvm, libvirt)" 