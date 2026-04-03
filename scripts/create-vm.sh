#!/bin/bash
set -e

# create-vm.sh - Create Proxmox VM for Lax media server
# Usage: ./create-vm.sh <vm-name> <vmid> [node]

# Configuration
DEFAULT_NODE="jupiter"  # Proxmox node to create VM on
DEBIAN_IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
VM_MEMORY="8192"        # 8GB RAM
VM_CORES="4"           # 4 CPU cores
VM_DISK="32G"          # 32GB disk
VM_STORAGE="local-lvm" # Storage pool

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

show_usage() {
    echo "Usage: $0 <vm-name> <vmid> [node]"
    echo ""
    echo "Arguments:"
    echo "  vm-name    Name of the VM (e.g., lax-new, lax-test)"
    echo "  vmid       Proxmox VM ID (e.g., 200, 201)"
    echo "  node       Proxmox node (default: $DEFAULT_NODE)"
    echo ""
    echo "Example: $0 lax-new 200 jupiter"
    exit 1
}

# Check arguments
if [ $# -lt 2 ]; then
    show_usage
fi

VM_NAME="$1"
VMID="$2"
NODE="${3:-$DEFAULT_NODE}"

log_info "Creating VM '$VM_NAME' with ID $VMID on node $NODE"

# Validate VMID is a number
if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
    log_error "VMID must be a number"
    exit 1
fi

# Check if VMID already exists
if qm status "$VMID" 2>/dev/null; then
    log_error "VM with ID $VMID already exists"
    exit 1
fi

log_info "1. Downloading Debian 13 cloud image..."
wget -q "$DEBIAN_IMAGE_URL" -O debian-13.qcow2

log_info "2. Creating VM template..."
qm create "$VMID" \
    --name "$VM_NAME" \
    --memory "$VM_MEMORY" \
    --cores "$VM_CORES" \
    --net0 virtio,bridge=vmbr0 \
    --scsihw virtio-scsi-pci \
    --scsi0 "$VM_STORAGE:$VM_DISK"

log_info "3. Importing disk image..."
qm importdisk "$VMID" debian-13.qcow2 "$VM_STORAGE"

log_info "4. Configuring cloud-init..."

# Create cloud-init configuration
CLOUD_INIT_DIR="/tmp/cloud-init-${VMID}"
mkdir -p "${CLOUD_INIT_DIR}"

# Create user-data file with both SSH keys
cat > "${CLOUD_INIT_DIR}/user-data" << 'EOF'
#cloud-config
users:
  - name: axl
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      # Axl's RSA key (replace with actual public key)
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... axl@local
      # Claw infrastructure key (replace with actual public key)
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... claw@eze

# Enable passwordless sudo
sudo:
  - ALL=(ALL) NOPASSWD:ALL

# Set hostname
hostname: ${VM_NAME}

# Configure network (DHCP)
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: false

# Update packages and install basic tools
package_update: true
package_upgrade: true
packages:
  - curl
  - git
  - htop
  - net-tools

# Run first boot commands
runcmd:
  - [systemctl, enable, --now, ssh]
  - [mkdir, -p, /home/axl/.ssh]
  - [chmod, 700, /home/axl/.ssh]
  - [chown, -R, axl:axl, /home/axl/.ssh]
EOF

# Create meta-data file
cat > "${CLOUD_INIT_DIR}/meta-data" << EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

# Upload cloud-init config to Proxmox
qm set ${VMID} \
    --cicustom "user=local:snippets/${VM_NAME}-user-data.yml,network=local:snippets/${VM_NAME}-network-config.yml"

# Note: In practice, you would upload these snippets to Proxmox first
# pvesh create /nodes/${NODE}/storage/local/content \
#     -filename "snippets/${VM_NAME}-user-data.yml" \
#     -content "$(cat ${CLOUD_INIT_DIR}/user-data)"
#
# pvesh create /nodes/${NODE}/storage/local/content \
#     -filename "snippets/${VM_NAME}-network-config.yml" \
#     -content "network: {config: disabled}"

# Clean up temp files
rm -rf "${CLOUD_INIT_DIR}"

log_info "5. Setting boot order..."
qm set "$VMID" --boot order=scsi0

log_info "6. Starting VM..."
qm start "$VMID"

log_info "7. Cleaning up temporary files..."
rm -f debian-13.qcow2

log_info "VM creation complete!"
echo ""
echo "VM Details:"
echo "  Name: $VM_NAME"
echo "  ID: $VMID"
echo "  Node: $NODE"
echo "  Specs: $VM_CORES cores, ${VM_MEMORY}MB RAM, $VM_DISK disk"
echo ""
echo "Next steps:"
echo "  1. Wait for VM to boot (approx 60 seconds)"
echo "  2. Run setup-docker.sh on the new VM"
echo "  3. Configure NFS mounts with prepare-storage.sh"
echo "  4. Deploy stack with deploy-stack.sh"