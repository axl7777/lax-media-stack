#!/bin/bash
set -e

# prepare-storage.sh - Set up NFS mounts for Lax media server
# Run this after setup-docker.sh

# Configuration
NFS_SERVER="mercure.home"  # or 10.9.0.20
MEDIA_EXPORTS=(
    ":/volume1/media"
    ":/volume1/media/dl"
    ":/volume1/media/dl/ultra.cc"
    ":/volume1/media/dl/seedhost.eu"
    ":/volume2/plex/Library/Application Support/Plex Media Server/Logs"
)

LOCAL_MOUNTS=(
    "/mnt/media"
    "/mnt/media/dl"
    "/mnt/media/ultra"
    "/mnt/media/seedhost"
    "/mnt/plex/logs"
)

DOCKER_VOLUME_PATHS=(
    "/var/lib/docker/volumes/media_media/_data"
    "/var/lib/docker/volumes/media_dl/_data"
    "/var/lib/docker/volumes/media_ultra/_data"
    "/var/lib/docker/volumes/syncthing_dl/_data"
    "/var/lib/docker/volumes/media_plex/_data"
)

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

install_nfs_client() {
    log_info "1. Installing NFS client utilities..."
    apt-get update
    apt-get install -y nfs-common
}

test_nfs_connection() {
    log_info "2. Testing NFS server connection..."
    
    if ping -c 1 -W 2 "$NFS_SERVER" > /dev/null 2>&1; then
        log_info "NFS server $NFS_SERVER is reachable"
    else
        log_error "Cannot reach NFS server $NFS_SERVER"
        log_warn "Trying IP address 10.9.0.20..."
        NFS_SERVER="10.9.0.20"
        if ping -c 1 -W 2 "$NFS_SERVER" > /dev/null 2>&1; then
            log_info "NFS server $NFS_SERVER is reachable"
        else
            log_error "Cannot reach NFS server. Please check network connectivity."
            exit 1
        fi
    fi
    
    # Test showmount
    if showmount -e "$NFS_SERVER" > /dev/null 2>&1; then
        log_info "NFS exports on $NFS_SERVER:"
        showmount -e "$NFS_SERVER"
    else
        log_warn "Cannot list NFS exports. Continuing anyway..."
    fi
}

create_mount_points() {
    log_info "3. Creating mount points..."
    
    # Create basic mount points
    for mount in "${LOCAL_MOUNTS[@]}"; do
        mkdir -p "$mount"
        chmod 755 "$mount"
        log_info "  Created: $mount"
    done
    
    # Create Docker volume directories
    for volume in "${DOCKER_VOLUME_PATHS[@]}"; do
        mkdir -p "$volume"
        chmod 755 "$volume"
        log_info "  Created Docker volume path: $volume"
    done
    
    # Set ownership for Docker volumes
    chown -R axl:axl /var/lib/docker/volumes/
}

configure_fstab() {
    log_info "4. Configuring /etc/fstab for persistent mounts..."
    
    # Backup existing fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d)
    
    # Add NFS mounts to fstab
    cat >> /etc/fstab << EOF

# Lax media server NFS mounts
$NFS_SERVER:/volume1/media    /mnt/media    nfs4    defaults,noatime,vers=4.1    0 0
$NFS_SERVER:/volume1/media/dl /mnt/media/dl nfs4    defaults,noatime,vers=4.1    0 0
$NFS_SERVER:/volume1/media/dl/ultra.cc /mnt/media/ultra nfs4 defaults,noatime,vers=4.1 0 0
$NFS_SERVER:/volume1/media/dl/seedhost.eu /mnt/media/seedhost nfs4 defaults,noatime,vers=4.1 0 0
$NFS_SERVER:/volume2/plex/Library/Application\ Support/Plex\ Media\ Server/Logs /mnt/plex/logs nfs4 defaults,noatime,vers=4.1 0 0
EOF
    
    log_info "fstab updated. Backup saved to /etc/fstab.backup.$(date +%Y%m%d)"
}

mount_all() {
    log_info "5. Mounting all filesystems..."
    
    # Mount from fstab
    mount -a
    
    # Verify mounts
    log_info "Current mounts:"
    mount | grep -E "nfs|mercure|volume"
    
    # Test write access
    TEST_FILE="/mnt/media/.write_test_$(date +%s)"
    if touch "$TEST_FILE" 2>/dev/null; then
        log_info "Write test successful on /mnt/media"
        rm -f "$TEST_FILE"
    else
        log_warn "Cannot write to /mnt/media. Checking permissions..."
        ls -la /mnt/media/
    fi
}

create_symlinks_for_docker() {
    log_info "6. Creating symlinks for Docker volumes..."
    
    # Create symlinks to match current lax structure
    ln -sf /mnt/media /var/lib/docker/volumes/media_media/_data
    ln -sf /mnt/media/dl /var/lib/docker/volumes/media_dl/_data
    ln -sf /mnt/media/ultra /var/lib/docker/volumes/media_ultra/_data
    ln -sf /mnt/media/seedhost /var/lib/docker/volumes/syncthing_dl/_data
    ln -sf /mnt/plex/logs /var/lib/docker/volumes/media_plex/_data
    
    log_info "Symlinks created for Docker volumes"
}

verify_storage() {
    log_info "7. Verifying storage setup..."
    
    echo "=== Storage Summary ==="
    df -h | grep -E "Filesystem|/mnt|mercure"
    
    echo ""
    echo "=== Mount Points ==="
    for mount in "${LOCAL_MOUNTS[@]}"; do
        if mountpoint -q "$mount"; then
            echo -e "${GREEN}✓${NC} $mount is mounted"
        else
            echo -e "${RED}✗${NC} $mount is NOT mounted"
        fi
    done
    
    echo ""
    echo "=== Docker Volume Paths ==="
    for volume in "${DOCKER_VOLUME_PATHS[@]}"; do
        if [ -L "$volume" ] || [ -d "$volume" ]; then
            echo -e "${GREEN}✓${NC} $volume exists"
            ls -la "$volume" | head -3
        else
            echo -e "${RED}✗${NC} $volume does not exist"
        fi
    done
}

main() {
    log_info "Starting storage preparation for Lax media server..."
    
    check_root
    install_nfs_client
    test_nfs_connection
    create_mount_points
    configure_fstab
    mount_all
    create_symlinks_for_docker
    verify_storage
    
    log_info "Storage preparation completed successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Verify all mounts are working: df -h"
    echo "  2. Test NFS access by creating a test file"
    echo "  3. Run deploy-stack.sh to deploy Docker containers"
    echo ""
    echo "Important: Reboot to verify persistent mounts work correctly."
}

# Run main function
main "$@"