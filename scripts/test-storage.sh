#!/bin/bash
set -e

# test-storage.sh - Test NFS connectivity for Docker volumes
# Run after setup-docker.sh to verify storage is ready

# Configuration
NFS_SERVER="mercure.home"
TEST_MOUNT="/tmp/test-nfs-mount"

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

check_nfs_client() {
    log_info "1. Checking NFS client installation..."
    
    if dpkg -l | grep -q nfs-common; then
        log_info "✓ nfs-common is installed"
    else
        log_error "nfs-common is not installed"
        log_info "Install with: apt-get install nfs-common"
        exit 1
    fi
    
    # Check if NFS services are running
    if systemctl is-active --quiet rpcbind || systemctl is-active --quiet rpc-statd; then
        log_info "✓ NFS client services are running"
    else
        log_warn "NFS client services not running (may start on demand)"
    fi
}

test_nfs_connectivity() {
    log_info "2. Testing NFS server connectivity..."
    
    # Try mercure.home first
    if ping -c 1 -W 2 "$NFS_SERVER" > /dev/null 2>&1; then
        log_info "✓ NFS server $NFS_SERVER is reachable"
    else
        log_warn "Cannot resolve $NFS_SERVER, trying IP..."
        NFS_SERVER="10.9.0.20"
        if ping -c 1 -W 2 "$NFS_SERVER" > /dev/null 2>&1; then
            log_info "✓ NFS server $NFS_SERVER (IP) is reachable"
        else
            log_error "Cannot reach NFS server at $NFS_SERVER"
            log_info "Check network connectivity to mercure (10.9.0.20)"
            exit 1
        fi
    fi
    
    # Test NFS export listing
    log_info "3. Testing NFS exports..."
    if timeout 5 showmount -e "$NFS_SERVER" > /dev/null 2>&1; then
        log_info "✓ NFS exports are accessible"
        echo ""
        showmount -e "$NFS_SERVER" | head -10
        echo ""
    else
        log_warn "Cannot list NFS exports (may require authentication)"
        log_info "This may be OK - Docker will handle mounting"
    fi
}

test_docker_nfs_volume() {
    log_info "4. Testing Docker NFS volume creation..."
    
    # Create a test Docker volume with NFS driver
    VOLUME_NAME="test-nfs-volume-$(date +%s)"
    
    log_info "Creating test Docker volume: $VOLUME_NAME"
    
    if docker volume create \
        --driver local \
        --opt type=nfs \
        --opt o=addr=$NFS_SERVER,rw,vers=4.1 \
        --opt device=":/volume1/media" \
        "$VOLUME_NAME" > /dev/null 2>&1; then
        
        log_info "✓ Docker NFS volume created successfully"
        
        # Test the volume
        log_info "Testing volume with a container..."
        if docker run --rm \
            -v "$VOLUME_NAME:/test" \
            alpine ls -la /test 2>/dev/null | head -5; then
            log_info "✓ Can read from NFS volume"
        else
            log_warn "Could not read from volume (may be empty)"
        fi
        
        # Clean up
        docker volume rm "$VOLUME_NAME" > /dev/null 2>&1
        log_info "Test volume removed"
        
    else
        log_error "Failed to create Docker NFS volume"
        log_info "Check:"
        log_info "  1. NFS server is running on mercure"
        log_info "  2. Exports are configured on mercure"
        log_info "  3. Firewall allows NFS traffic (port 2049)"
        exit 1
    fi
}

verify_required_paths() {
    log_info "5. Verifying required NFS paths exist..."
    
    # Paths required by the media stack
    REQUIRED_PATHS=(
        ":/volume1/media"
        ":/volume1/media/dl"
        ":/volume1/media/dl/ultra.cc"
        ":/volume1/media/dl/seedhost.eu"
        ":/volume2/plex/Library/Application Support/Plex Media Server/Logs"
    )
    
    log_info "Checking NFS paths (this may take a moment)..."
    
    for path in "${REQUIRED_PATHS[@]}"; do
        # Create a test mount to check path
        TEST_MOUNT="/tmp/test-$(echo "$path" | md5sum | cut -c1-8)"
        mkdir -p "$TEST_MOUNT"
        
        if timeout 10 mount -t nfs4 "$NFS_SERVER:$path" "$TEST_MOUNT" 2>/dev/null; then
            log_info "✓ $path is accessible"
            umount "$TEST_MOUNT" 2>/dev/null
            rmdir "$TEST_MOUNT"
        else
            log_warn "⚠ $path may not be accessible"
            rmdir "$TEST_MOUNT" 2>/dev/null
        fi
    done
    
    log_info "Note: Some paths may require proper permissions on the NFS server"
}

generate_storage_report() {
    log_info "6. Storage readiness report..."
    
    echo ""
    echo "=== STORAGE READINESS REPORT ==="
    echo "Date: $(date)"
    echo "NFS Server: $NFS_SERVER"
    echo ""
    
    # System info
    echo "System:"
    echo "  OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
    echo "  Kernel: $(uname -r)"
    echo ""
    
    # NFS info
    echo "NFS Client:"
    dpkg -l nfs-common 2>/dev/null | grep nfs-common | awk '{print "  Version: " $3}'
    echo ""
    
    # Docker info
    echo "Docker:"
    docker --version 2>/dev/null | head -1
    echo ""
    
    # Recommendations
    echo "RECOMMENDATIONS:"
    echo "  1. All required NFS paths should be accessible"
    echo "  2. Docker NFS volume creation should succeed"
    echo "  3. Network connectivity to mercure (10.9.0.20) is essential"
    echo ""
    echo "If tests pass, storage is ready for media stack deployment."
}

main() {
    log_info "Testing storage configuration for Lax media server..."
    
    check_nfs_client
    test_nfs_connectivity
    test_docker_nfs_volume
    verify_required_paths
    generate_storage_report
    
    log_info "Storage testing completed!"
    echo ""
    echo "Next: If all tests pass, you can deploy the media stack."
    echo "Run: ./scripts/deploy-stack.sh (to be created)"
}

# Run main function
main "$@"