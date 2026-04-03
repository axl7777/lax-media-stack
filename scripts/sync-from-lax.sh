#!/bin/bash
set -e

# sync-from-lax.sh - Sync configuration from running lax instance to GitHub
# Run this from OpenClaw after making changes on lax

# Configuration
LAX_HOST="lax"
LAX_USER="axl"
CONFIG_DIRS=("/home/axl/media" "/home/axl/core" "/home/axl/monitor" "/home/axl/syncthing")
SSH_KEY="$HOME/.openclaw/workspace/.ssh/eze_claw"

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

check_dependencies() {
    log_info "1. Checking dependencies..."
    
    # Check SSH key exists
    if [ ! -f "$SSH_KEY" ]; then
        log_error "SSH key not found: $SSH_KEY"
        exit 1
    fi
    
    # Check git is available
    if ! command -v git &> /dev/null; then
        log_error "git is not installed"
        exit 1
    fi
}

test_lax_connection() {
    log_info "2. Testing connection to lax..."
    
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$LAX_USER@$LAX_HOST" "echo 'Connection successful'" > /dev/null 2>&1; then
        log_info "Connected to $LAX_HOST"
    else
        log_error "Cannot connect to $LAX_HOST"
        exit 1
    fi
}

sync_docker_compose_files() {
    log_info "3. Syncing Docker Compose files..."
    
    # Create backup directory
    BACKUP_DIR="/tmp/lax-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    for dir in "${CONFIG_DIRS[@]}"; do
        dir_name=$(basename "$dir")
        log_info "  Syncing $dir_name..."
        
        # Copy docker-compose.yml if it exists
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$LAX_USER@$LAX_HOST" "test -f $dir/docker-compose.yml" > /dev/null 2>&1; then
            # Backup original
            cp -f "config/docker-compose.$dir_name.yml" "$BACKUP_DIR/docker-compose.$dir_name.yml.backup" 2>/dev/null || true
            
            # Download new version
            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$LAX_USER@$LAX_HOST" "cat $dir/docker-compose.yml" > "config/docker-compose.$dir_name.yml"
            
            # Check if file changed
            if diff -q "config/docker-compose.$dir_name.yml" "$BACKUP_DIR/docker-compose.$dir_name.yml.backup" > /dev/null 2>&1; then
                log_info "    No changes in $dir_name"
                rm -f "$BACKUP_DIR/docker-compose.$dir_name.yml.backup"
            else
                log_info "    Updated $dir_name"
            fi
        else
            log_warn "    No docker-compose.yml in $dir"
        fi
        
        # Sync .env file if it exists
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$LAX_USER@$LAX_HOST" "test -f $dir/.env" > /dev/null 2>&1; then
            # Create sanitized version (remove sensitive data)
            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$LAX_USER@$LAX_HOST" "cat $dir/.env" | \
                sed -E 's/(PASS|PASSWORD|SECRET|TOKEN|KEY)=.*/\1=REDACTED/g' \
                > "config/.env.$dir_name.template"
            log_info "    Created .env template for $dir_name"
        fi
    done
    
    # Clean up empty backup directory
    if [ -z "$(ls -A "$BACKUP_DIR")" ]; then
        rmdir "$BACKUP_DIR"
    else
        log_info "Backups saved to: $BACKUP_DIR"
    fi
}

sync_mount_config() {
    log_info "4. Syncing mount configuration..."
    
    # Get current NFS mounts
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$LAX_USER@$LAX_HOST" "mount | grep -E 'nfs|mercure|volume'" > "config/mounts.current.txt"
    
    # Get fstab entries
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$LAX_USER@$LAX_HOST" "grep -E 'nfs|mercure|volume' /etc/fstab" > "config/fstab.entries.txt" 2>/dev/null || true
    
    log_info "    Mount configuration saved"
}

commit_and_push() {
    log_info "5. Committing and pushing changes..."
    
    # Check if there are any changes
    if git status --porcelain | grep -q "."; then
        log_info "  Changes detected:"
        git status --porcelain
        
        # Add all files
        git add .
        
        # Commit with timestamp
        COMMIT_MSG="Sync from lax $(date '+%Y-%m-%d %H:%M:%S')"
        git commit -m "$COMMIT_MSG"
        
        # Push to GitHub
        if git push origin main; then
            log_info "  Successfully pushed to GitHub"
            
            # Show commit info
            echo ""
            echo "Commit: $(git log -1 --oneline)"
            echo "URL: https://github.com/axl7777/lax-media-stack/commit/$(git rev-parse HEAD)"
        else
            log_error "  Failed to push to GitHub"
            exit 1
        fi
    else
        log_info "  No changes to commit"
    fi
}

generate_report() {
    log_info "6. Generating sync report..."
    
    echo ""
    echo "=== Sync Report ==="
    echo "Timestamp: $(date)"
    echo "Source: $LAX_HOST"
    echo "Repository: https://github.com/axl7777/lax-media-stack"
    
    # Show what was synced
    echo ""
    echo "Synced files:"
    find config -name "*.yml" -o -name "*.txt" -o -name "*.template" | sort | while read file; do
        echo "  - $file"
    done
    
    # Show git status
    echo ""
    echo "Git status:"
    git status --short
    
    # Show last commit
    echo ""
    echo "Last commit:"
    git log -1 --oneline
}

main() {
    log_info "Starting sync from lax to GitHub..."
    
    # Change to repository directory
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    cd "$REPO_DIR"
    
    check_dependencies
    test_lax_connection
    sync_docker_compose_files
    sync_mount_config
    commit_and_push
    generate_report
    
    log_info "Sync completed successfully!"
    echo ""
    echo "Next:"
    echo "  1. Review changes on GitHub: https://github.com/axl7777/lax-media-stack"
    echo "  2. Test updated configuration"
    echo "  3. Deploy changes to new VMs when ready"
}

# Run main function
main "$@"