# Use Ubuntu 24.04 as base image
FROM ubuntu:24.04

# Set environment variables
ENV GO_VERSION=1.23.1
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/usr/local/go/bin:$PATH
ENV GOPATH=/home/developer/go
ENV PATH=$GOPATH/bin:$PATH

# Create developer user (equivalent to vagrant user)
RUN useradd -m -s /bin/bash developer && \
    usermod -aG sudo developer && \
    echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Update packages (equivalent to upgrade-packages provision)
RUN apt update

# Install basic packages (equivalent to install-basic-packages provision)
RUN apt install -y \
    make \
    git \
    gcc \
    curl \
    unzip \
    direnv \
    sudo

# Install Go (equivalent to install-golang provision)
RUN curl -fsSL "https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz" | tar Cxz /usr/local && \
    echo 'PATH=/usr/local/go/bin:$PATH' >> /etc/environment && \
    echo 'export GOPATH=/home/developer/go' >> /etc/profile.d/sh.local && \
    echo 'export PATH=$GOPATH/bin:$PATH' >> /etc/profile.d/sh.local

# Install virtualization tools (limited functionality in containers)
# Note: This won't work the same as in VMs - requires privileged mode
RUN apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils || true && \
    usermod -aG libvirt developer || true && \
    usermod -aG kvm developer || true

# Install Nix and Devbox (equivalent to install-devbox provision)
RUN curl -L https://nixos.org/nix/install | sh -s -- --daemon && \
    curl -L -o /usr/local/bin/devbox https://releases.jetify.com/devbox && \
    chmod +x /usr/local/bin/devbox

# Set working directory
WORKDIR /home/developer/flintlock

# Switch to developer user
USER developer

# Expose ports (equivalent to port forwarding)
EXPOSE 9090 9091

# Set default command
CMD ["/bin/bash"] 