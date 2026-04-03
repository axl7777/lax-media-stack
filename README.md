# Lax Media Stack - Infrastructure as Code

This repository contains the complete configuration and deployment scripts for the Lax media server.

## Overview

Lax is a Debian 13 VM running Docker containers for media management, including:
- **Media Management:** Sonarr, Radarr, Prowlarr, Bazarr
- **Automation:** Pulsarr, Kometa, Decluttarr
- **Monitoring:** Node-exporter, Beszel-agent
- **Management:** Tugtainer, Portainer, Dozzle, Organizr

## Architecture

- **VM:** 4 vCPUs, 8GB RAM, 32GB disk
- **OS:** Debian 13 (trixie)
- **Storage:** NFS mounts from mercure (Synology NAS)
- **Network:** 10.9.0.0/24 subnet, Tailscale access

## Quick Start

1. **Create VM:** `scripts/create-vm.sh <name> <vmid>`
2. **Setup Docker:** `scripts/setup-docker.sh`
3. **Prepare Storage:** `scripts/prepare-storage.sh`
4. **Deploy Stack:** `scripts/deploy-stack.sh`

## Repository Structure

```
├── scripts/           # Deployment scripts
├── config/           # Service configurations
├── docs/            # Documentation
└── terraform/       # Infrastructure as Code (optional)
```

## Prerequisites

- Proxmox VE cluster access
- SSH key with sudo privileges on Proxmox nodes
- NFS server (mercure) accessible
- GitHub repository for configuration storage

## Secrets Management

Sensitive data is stored in GitHub Secrets:
- `PROXMOX_API_TOKEN`: Proxmox API token
- `SSH_PRIVATE_KEY`: SSH key for VM access
- `DOCKER_REGISTRY_CREDS`: Docker registry credentials

## Deployment

See [docs/setup-guide.md](docs/setup-guide.md) for detailed instructions.