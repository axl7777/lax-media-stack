#!/bin/bash
set -e

# setup-docker.sh - Install Docker and dependencies on Debian 13
# Run this on the new VM after creation

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (use sudo)"
        exit 1
    fi
}

update_system() {
    log_info "1. Updating system packages..."
    apt-get update
    apt-get upgrade -y
}

install_dependencies() {
    log_info "2. Installing dependencies..."
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        git \
        nfs-common \
        htop \
        net-tools \
        ufw \
        software-properties-common
}

install_docker() {
    log_info "3. Installing Docker..."
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt-get update
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
}

configure_docker() {
    log_info "4. Configuring Docker..."
    
    # Create docker group if it doesn't exist
    if ! getent group docker > /dev/null; then
        groupadd docker
    fi
    
    # Add axl user to docker group
    if id "axl" &>/dev/null; then
        usermod -aG docker axl
    else
        log_warn "User 'axl' not found, creating..."
        useradd -m -s /bin/bash axl
        usermod -aG docker axl
    fi
    
    # Configure Docker daemon
    cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
}

install_docker_compose() {
    log_info "5. Installing Docker Compose (standalone)..."
    
    # Download Docker Compose binary
    COMPOSE_VERSION="v2.27.0"
    curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create symbolic link
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
}

configure_environment() {
    log_info "6. Configuring environment..."
    
    # Create directories
    mkdir -p /home/axl/{media,core,monitor,syncthing}
    chown -R axl:axl /home/axl
    
    # Set up SSH key (if not present)
    if [ ! -f /home/axl/.ssh/authorized_keys ]; then
        mkdir -p /home/axl/.ssh
        chmod 700 /home/axl/.ssh
        # SSH key will be added via cloud-init or manually
        touch /home/axl/.ssh/authorized_keys
        chmod 600 /home/axl/.ssh/authorized_keys
        chown -R axl:axl /home/axl/.ssh
    fi
    
    # Configure sudo for axl user
    echo "axl ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/axl
    chmod 440 /etc/sudoers.d/axl
}

setup_firewall() {
    log_info "7. Configuring firewall..."
    
    # Enable UFW
    ufw --force enable
    
    # Allow SSH
    ufw allow ssh
    
    # Allow Docker traffic (internal)
    ufw allow from 10.9.0.0/24
    ufw allow from 172.16.0.0/12  # Docker internal networks
    
    log_info "Firewall rules applied"
}

verify_installation() {
    log_info "8. Verifying installation..."
    
    # Check Docker
    if docker --version; then
        log_info "Docker version: $(docker --version | cut -d' ' -f3)"
    else
        log_error "Docker installation failed"
        exit 1
    fi
    
    # Check Docker Compose
    if docker-compose --version; then
        log_info "Docker Compose version: $(docker-compose --version | cut -d' ' -f3)"
    else
        log_error "Docker Compose installation failed"
        exit 1
    fi
    
    # Test Docker run
    if docker run --rm hello-world | grep -q "Hello from Docker"; then
        log_info "Docker test successful"
    else
        log_error "Docker test failed"
        exit 1
    fi
}

main() {
    log_info "Starting Docker setup for Lax media server..."
    
    check_root
    update_system
    install_dependencies
    install_docker
    configure_docker
    install_docker_compose
    configure_environment
    setup_firewall
    verify_installation
    
    log_info "Docker setup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Reboot or log out/in for group changes to take effect"
    echo "  2. Run prepare-storage.sh to set up NFS mounts"
    echo "  3. Run deploy-stack.sh to deploy media stack"
    echo ""
    echo "To test:"
    echo "  sudo -u axl docker ps"
    echo "  sudo -u axl docker-compose --version"
}

# Run main function
main "$@"