# Sync Guide: Lax Configuration to GitHub

This guide explains how to sync configuration changes from your running lax instance to the GitHub repository.

## Quick Sync Script

The easiest way is to use the sync script:

```bash
./scripts/sync-from-lax.sh
```

This will:
1. Connect to lax via SSH
2. Download all Docker Compose files
3. Create sanitized .env templates
4. Save mount configurations
5. Commit and push to GitHub

## Manual Sync Steps

If you prefer manual control:

### 1. Make Changes on Lax
```bash
# SSH into lax
ssh -i ~/.openclaw/workspace/.ssh/eze_claw claw@lax

# Make your changes (edit compose files, mounts, etc.)
sudo -u axl nano /home/axl/media/docker-compose.yml
```

### 2. Copy Changes to OpenClaw
```bash
# From OpenClaw, copy the changed files
scp -i ~/.openclaw/workspace/.ssh/eze_claw claw@lax:/home/axl/media/docker-compose.yml config/docker-compose.media.yml
```

### 3. Update Repository
```bash
# Go to repository
cd /home/node/.openclaw/workspace/lax-media-stack

# Check changes
git diff

# Add and commit
git add config/docker-compose.media.yml
git commit -m "Update: Media stack configuration"

# Push to GitHub
git push origin main
```

## What Gets Synced

### Automatically Synced:
- `/home/axl/media/docker-compose.yml` → `config/docker-compose.media.yml`
- `/home/axl/core/docker-compose.yml` → `config/docker-compose.core.yml`
- `/home/axl/monitor/docker-compose.yml` → `config/docker-compose.monitor.yml`
- `/home/axl/syncthing/docker-compose.yml` → `config/docker-compose.syncthing.yml`

### Sanitized Sync:
- `.env` files → `.env.template` (sensitive data redacted)
- Mount configurations → `config/mounts.current.txt`

### Manual Sync Needed:
- Service-specific configs (Sonarr/Radarr databases, etc.)
- Custom scripts
- Cron jobs

## Security Considerations

### Sensitive Data Handling:
The sync script automatically redacts:
- Passwords (`PASS=`, `PASSWORD=`)
- Secrets (`SECRET=`)
- Tokens (`TOKEN=`)
- API keys (`KEY=`)

**Never commit actual credentials to GitHub!**

### SSH Key Requirements:
The sync script uses the `eze_claw` SSH key located at:
```
~/.openclaw/workspace/.ssh/eze_claw
```

## Testing Sync

Test the sync process without committing:
```bash
# Dry run - see what would be synced
./scripts/sync-from-lax.sh --dry-run  # (Add this flag if implemented)

# Or manually test connection
ssh -i ~/.openclaw/workspace/.ssh/eze_claw claw@lax "ls -la /home/axl/media/"
```

## Common Sync Scenarios

### Scenario 1: Added New Service
1. Add service to `docker-compose.yml` on lax
2. Run sync script
3. Review changes on GitHub
4. Update deployment scripts if needed

### Scenario 2: Changed Mount Points
1. Update NFS mounts on lax
2. Run sync script
3. Update `prepare-storage.sh` if mount structure changed
4. Test new mounts on test VM

### Scenario 3: Updated Environment Variables
1. Update `.env` file on lax
2. Run sync script (creates sanitized template)
3. Update `config/.env.template` with new variables
4. Document changes in commit message

## Troubleshooting

### "Permission denied" when connecting to lax
- Check SSH key permissions: `chmod 600 ~/.openclaw/workspace/.ssh/eze_claw`
- Verify key is added to lax: `ssh-copy-id -i ~/.openclaw/workspace/.ssh/eze_claw.pub claw@lax`

### "No changes to commit"
- The files haven't changed since last sync
- Check if you're in the right directory
- Verify connection to lax is working

### Git push fails
- Check GitHub token permissions
- Verify repository URL: `git remote -v`
- Check network connectivity to GitHub

## Best Practices

1. **Sync regularly** - After any configuration change
2. **Review changes** - Always check `git diff` before committing
3. **Use descriptive commit messages** - Explain what changed and why
4. **Test after sync** - Verify the repository can deploy a working VM
5. **Keep credentials separate** - Never commit real passwords/tokens

## Related Files
- `scripts/sync-from-lax.sh` - Main sync script
- `scripts/deploy-stack.sh` - Deployment script (to be created)
- `config/.env.template` - Environment variable template
- `.gitignore` - Files to exclude from Git

## Next Steps
After syncing configuration:
1. Test deployment with updated configuration
2. Update documentation if needed
3. Consider automating sync with cron job
4. Set up GitHub Actions for automated testing