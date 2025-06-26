#!/usr/bin/env bash

# Setup script for Kata Containers with Firecracker
# Uses the existing liquid-metal-containerd-provision.sh for base components

set -eu

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

KATA_VERSION="3.8.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROVISION_SCRIPT="$SCRIPT_DIR/liquid-metal-containerd-provision.sh"

log() {
    echo -e "${GREEN}[SETUP]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

check_requirements() {
    log "Checking requirements..."
    
    # Check if we're on Linux
    if [ "$(uname)" != "Linux" ]; then
        error "This script must be run on Linux"
    fi
    
    # Check if we're running as root
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (use sudo)"
    fi
    
    # Check if KVM is available
    if [ ! -c /dev/kvm ]; then
        error "/dev/kvm not found. KVM is required for virtualization."
    fi
    
    # Check if provision script exists
    if [ ! -f "$PROVISION_SCRIPT" ]; then
        error "Provision script not found at $PROVISION_SCRIPT"
    fi
    
    # Make provision script executable
    chmod +x "$PROVISION_SCRIPT"
    
    log "Requirements check passed ✓"
}

install_base_components() {
    log "Installing base components using provision script..."
    
    # Install required apt packages
    log "Installing apt packages..."
    "$PROVISION_SCRIPT" apt
    
    # Install firecracker
    log "Installing Firecracker..."
    "$PROVISION_SCRIPT" firecracker
    
    # Install containerd in dev mode (simpler setup)
    log "Installing containerd in dev mode..."
    "$PROVISION_SCRIPT" containerd --dev
    
    log "Base components installed ✓"
}

install_kata_containers() {
    log "Installing Kata Containers via APT repository..."
    
    # Install required packages for adding repository
    apt-get update
    apt-get install -y software-properties-common curl gpg
    
    # Add Kata Containers repository
    log "Adding Kata Containers repository..."
    curl -fsSL https://github.com/kata-containers/kata-containers/releases/download/3.18.0/kata-static-3.18.0-amd64.tar.xz -o /tmp/kata-static.tar.xz
    
    if [ -f /tmp/kata-static.tar.xz ]; then
        log "Extracting Kata Containers..."
        cd /tmp
        tar -xf kata-static.tar.xz
        
        # Create kata directory
        mkdir -p /opt/kata
        
        # Copy contents
        cp -r opt/kata/* /opt/kata/
        
        # Create symlinks for kata binaries
        log "Creating kata runtime symlinks..."
        ln -sf /opt/kata/bin/kata-runtime /usr/local/bin/kata-runtime
        ln -sf /opt/kata/bin/containerd-shim-kata-v2 /usr/local/bin/containerd-shim-kata-v2
        
        # Fix permissions
        chmod +x /opt/kata/bin/*
        
        # Clean up
        rm -rf /tmp/kata-static.tar.xz /tmp/opt
        
        log "Kata Containers installed successfully ✓"
    else
        error "Failed to download Kata Containers"
    fi
}

setup_devmapper_snapshotter() {
    log "Setting up devmapper snapshotter for Firecracker..."
    
    # Create devmapper setup script
    cat > /tmp/setup-devmapper.sh << 'EOF'
#!/bin/bash
set -ex

DATA_DIR=/var/lib/containerd-dev/io.containerd.snapshotter.v1.devmapper
POOL_NAME=kata-devpool

mkdir -p ${DATA_DIR}

# Create data file
touch "${DATA_DIR}/data"
truncate -s 100G "${DATA_DIR}/data"

# Create metadata file
touch "${DATA_DIR}/meta"
truncate -s 10G "${DATA_DIR}/meta"

# Allocate loop devices
DATA_DEV=$(losetup --find --show "${DATA_DIR}/data")
META_DEV=$(losetup --find --show "${DATA_DIR}/meta")

# Define thin-pool parameters
SECTOR_SIZE=512
DATA_SIZE="$(blockdev --getsize64 -q ${DATA_DEV})"
LENGTH_IN_SECTORS=$(bc <<< "${DATA_SIZE}/${SECTOR_SIZE}")
DATA_BLOCK_SIZE=128
LOW_WATER_MARK=32768

# Create a thin-pool device
dmsetup create "${POOL_NAME}" \
    --table "0 ${LENGTH_IN_SECTORS} thin-pool ${META_DEV} ${DATA_DEV} ${DATA_BLOCK_SIZE} ${LOW_WATER_MARK}"

echo "Devmapper snapshotter setup complete"
echo "Pool name: ${POOL_NAME}"
echo "Data directory: ${DATA_DIR}"
EOF

    chmod +x /tmp/setup-devmapper.sh
    /tmp/setup-devmapper.sh
    
    # Add devmapper configuration to containerd config
    local containerd_config="/etc/containerd/config-dev.toml"
    
    if ! grep -q "devmapper" "$containerd_config"; then
        log "Adding devmapper configuration to containerd..."
        cat >> "$containerd_config" << EOF

[plugins."io.containerd.snapshotter.v1.devmapper"]
pool_name = "kata-devpool"
root_path = "/var/lib/containerd-dev/io.containerd.snapshotter.v1.devmapper"
base_image_size = "10GB"
discard_blocks = true
EOF
    fi
    
    # Create reload script for reboots
    cat > /usr/local/bin/reload-devmapper.sh << 'EOF'
#!/bin/bash
set -ex

DATA_DIR=/var/lib/containerd-dev/io.containerd.snapshotter.v1.devmapper
POOL_NAME=kata-devpool

# Allocate loop devices
DATA_DEV=$(losetup --find --show "${DATA_DIR}/data")
META_DEV=$(losetup --find --show "${DATA_DIR}/meta")

# Define thin-pool parameters
SECTOR_SIZE=512
DATA_SIZE="$(blockdev --getsize64 -q ${DATA_DEV})"
LENGTH_IN_SECTORS=$(bc <<< "${DATA_SIZE}/${SECTOR_SIZE}")
DATA_BLOCK_SIZE=128
LOW_WATER_MARK=32768

# Create a thin-pool device
dmsetup create "${POOL_NAME}" \
    --table "0 ${LENGTH_IN_SECTORS} thin-pool ${META_DEV} ${DATA_DEV} ${DATA_BLOCK_SIZE} ${LOW_WATER_MARK}"
EOF

    chmod +x /usr/local/bin/reload-devmapper.sh
    
    # Create systemd service for devmapper reload
    cat > /etc/systemd/system/kata-devmapper-reload.service << EOF
[Unit]
Description=Kata Devmapper reload script
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/reload-devmapper.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable kata-devmapper-reload.service
    
    log "Devmapper snapshotter configured ✓"
}

configure_kata_firecracker() {
    log "Configuring Kata Containers to use Firecracker..."
    
    # Switch to Firecracker hypervisor
    /opt/kata/bin/kata-manager -S clh 2>/dev/null || /opt/kata/bin/kata-manager -S fc
    
    # Update containerd config to add kata-fc runtime with devmapper snapshotter
    local containerd_config="/etc/containerd/config-dev.toml"
    
    if ! grep -q "kata-fc" "$containerd_config"; then
        log "Adding Kata Firecracker runtime to containerd config..."
        cat >> "$containerd_config" << EOF

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc]
  runtime_type = "io.containerd.kata-fc.v2"
  snapshotter = "devmapper"
EOF
    fi
    
    # Create kata-fc shim script
    cat > /usr/local/bin/containerd-shim-kata-fc-v2 << 'EOF'
#!/bin/bash
export KATA_CONF_FILE=/etc/kata-containers/configuration-fc.toml
exec /opt/kata/bin/containerd-shim-kata-v2 "$@"
EOF

    chmod +x /usr/local/bin/containerd-shim-kata-fc-v2
    
    # Restart containerd
    systemctl restart containerd-dev.service
    
    log "Kata Containers configured for Firecracker ✓"
}

create_runtime_class() {
    log "Creating Kubernetes RuntimeClass for Kata Containers..."
    
    cat > /tmp/kata-runtimeclass.yaml << EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-fc
handler: kata-fc
overhead:
  podFixed:
    memory: "130Mi"
    cpu: "250m"
EOF
    
    if command -v kubectl > /dev/null; then
        kubectl apply -f /tmp/kata-runtimeclass.yaml 2>/dev/null || true
        log "RuntimeClass created (if kubectl is configured) ✓"
    else
        log "RuntimeClass definition saved to /tmp/kata-runtimeclass.yaml"
        log "Apply it with: kubectl apply -f /tmp/kata-runtimeclass.yaml"
    fi
}

test_setup() {
    log "Testing the setup..."
    
    # Check if kata-runtime is working
    if /opt/kata/bin/kata-runtime --version > /dev/null 2>&1; then
        log "Kata runtime is working ✓"
    else
        warn "Kata runtime test failed"
    fi
    
    # Check if containerd is running
    if systemctl is-active --quiet containerd-dev.service; then
        log "Containerd service is running ✓"
    else
        warn "Containerd service is not running"
    fi
    
    # Check if devmapper pool exists
    if dmsetup ls | grep -q kata-devpool; then
        log "Devmapper pool is active ✓"
    else
        warn "Devmapper pool is not active"
    fi
    
    # Show firecracker version
    if command -v firecracker > /dev/null; then
        local fc_version=$(firecracker --version 2>&1 | head -1)
        log "Firecracker version: $fc_version ✓"
    else
        warn "Firecracker binary not found in PATH"
    fi
}

print_usage_instructions() {
    log "Setup complete! 🎉"
    echo
    echo "Usage instructions:"
    echo "=================="
    echo
    echo "1. Test with Docker (if installed):"
    echo "   docker run --runtime io.containerd.kata-fc.v2 --rm busybox uname -a"
    echo
    echo "2. Test with containerd directly:"
    echo "   ctr run --snapshotter devmapper --runtime io.containerd.kata-fc.v2 --rm docker.io/library/busybox:latest test uname -a"
    echo
    echo "3. Use with Kubernetes:"
    echo "   Add 'runtimeClassName: kata-fc' to your pod spec"
    echo
    echo "Configuration files:"
    echo "- Kata config: /etc/kata-containers/configuration-fc.toml"
    echo "- Containerd config: /etc/containerd/config-dev.toml"
    echo
    echo "Services:"
    echo "- Containerd: systemctl status containerd-dev.service"
    echo "- Devmapper reload: systemctl status kata-devmapper-reload.service"
    echo
    echo "To verify Kata is running in a VM, check that the kernel version"
    echo "inside the container differs from the host kernel version."
    echo
}

main() {
    log "Starting Kata Containers setup with Firecracker..."
    
    check_requirements
    install_base_components
    install_kata_containers
    setup_devmapper_snapshotter
    configure_kata_firecracker
    create_runtime_class
    test_setup
    print_usage_instructions
}

main "$@" 