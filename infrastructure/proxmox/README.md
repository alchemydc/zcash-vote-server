# Proxmox Deployment for zcash-vote-server

Coming soon! Proxmox deployment support is planned for future releases.

## Overview

Proxmox Virtual Environment (Proxmox VE) is an open-source virtualization platform ideal for self-hosted, bare-metal, and on-premises deployments. This makes it perfect for validator operators who want full control over their infrastructure without relying on cloud providers.

## Planned Features

### Terraform/OpenTofu Integration
- Automated VM provisioning via Proxmox API
- Cloud-init integration for automated setup
- Network configuration (bridges, VLANs, static IPs)
- Storage pool management
- Backup scheduling via Proxmox VE

### Deployment Options
- **Terraform**: Automated infrastructure provisioning
- **Ansible**: Configuration management (future)
- **Manual**: Step-by-step deployment guide

## Prerequisites (When Implemented)

### Proxmox Environment
- Proxmox VE 7.0 or later
- API access (token-based authentication)
- Network access to Proxmox API (typically port 8006)
- Storage pool with sufficient space (100GB+ recommended)

### VM Template
- Ubuntu 22.04 LTS cloud image template pre-configured
- Cloud-init support enabled
- Template should include qemu-guest-agent

### Network Requirements
- Network bridge configured (e.g., vmbr0)
- IP address allocation plan (DHCP or static)
- Access to validator P2P network (port 26656)
- Optional: VLAN tagging support

## Proxmox-Specific Considerations

### Advantages
- **Full Control**: Own your infrastructure, no cloud vendor lock-in
- **Cost Effective**: One-time hardware cost vs recurring cloud fees
- **Privacy**: Data stays on your hardware
- **Flexibility**: Customize hardware for your needs
- **High Availability**: Built-in clustering and HA features

### Challenges
- **Initial Setup**: Requires Proxmox expertise
- **Maintenance**: You manage hardware, updates, and failures
- **Networking**: More complex than cloud provider abstractions
- **Templates**: Must create and maintain VM templates
- **Backup**: Manual backup strategy required

## Architecture

### Typical Deployment
```
┌─────────────────────────────────────┐
│     Proxmox VE Host/Cluster        │
│                                     │
│  ┌──────────────────────────────┐  │
│  │  Ubuntu 22.04 VM Template   │  │
│  │  (Cloud-init enabled)        │  │
│  └──────────────────────────────┘  │
│              │                      │
│              ▼ Clone                │
│  ┌──────────────────────────────┐  │
│  │  Validator VM                │  │
│  │  zcash-vote-server          │  │
│  │  + CometBFT                 │  │
│  │                              │  │
│  │  vmbr0 ─────────► Network  │  │
│  │  100GB Disk                 │  │
│  │  2 vCPU, 8GB RAM           │  │
│  └──────────────────────────────┘  │
│                                     │
└─────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: Terraform Provider Integration
- Use Telmate Proxmox provider for Terraform
- VM cloning from template
- Cloud-init configuration
- Network setup (bridge, VLAN, IP)
- Storage configuration

### Phase 2: Enhanced Automation
- Ansible playbooks for post-configuration
- Automated template creation
- Backup script integration
- Monitoring setup

### Phase 3: High Availability
- Multi-node Proxmox cluster support
- HA configuration for validators
- Automated failover testing

## Template Preparation Guide

When implementation is complete, you'll need to prepare a template:

### 1. Download Ubuntu Cloud Image
```bash
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

### 2. Create VM Template
```bash
# Create VM
qm create 9000 --name ubuntu-22.04-template --memory 2048 --net0 virtio,bridge=vmbr0

# Import disk
qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm

# Attach disk
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0

# Configure cloud-init
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0

# Set other options
qm set 9000 --agent enabled=1

# Convert to template
qm template 9000
```

### 3. Test Template
```bash
# Clone and test
qm clone 9000 100 --name test-vm
qm start 100
```

## Configuration Variables (Planned)

Similar to GCP, configuration will use environment variables:

```bash
# Proxmox Connection
export TF_VAR_proxmox_api_url="https://proxmox.example.com:8006/api2/json"
export TF_VAR_proxmox_api_token_id="terraform@pam!mytoken"
export TF_VAR_proxmox_api_token_secret="your-secret-here"

# VM Configuration
export TF_VAR_validator_name="validator-01"
export TF_VAR_template_id="9000"
export TF_VAR_target_node="pve"
export TF_VAR_cpu_cores="2"
export TF_VAR_memory_mb="8192"
export TF_VAR_disk_size_gb="100"

# Network Configuration
export TF_VAR_network_bridge="vmbr0"
export TF_VAR_network_vlan=""  # Optional VLAN tag
export TF_VAR_ip_address="192.168.1.100/24"  # Or "dhcp"
export TF_VAR_gateway="192.168.1.1"
export TF_VAR_nameservers="8.8.8.8,8.8.4.4"

# Storage
export TF_VAR_storage_pool="local-lvm"
```

## In the Meantime: Manual Deployment

Until automated Proxmox deployment is implemented, you can manually deploy:

### 1. Create VM from Template
```bash
# Clone template
qm clone 9000 <VMID> --name validator-01 --full

# Resize disk if needed
qm resize <VMID> scsi0 100G

# Configure resources
qm set <VMID> --cores 2 --memory 8192

# Configure network (example with static IP)
qm set <VMID> --ipconfig0 ip=192.168.1.100/24,gw=192.168.1.1

# Start VM
qm start <VMID>
```

### 2. SSH and Run Installation Scripts
```bash
# Wait for VM to boot, then SSH
ssh ubuntu@<VM_IP>

# Download and run common scripts
curl -O https://raw.githubusercontent.com/alchemydc/zcash-vote-server/main/infrastructure/common/scripts/install-base.sh
curl -O https://raw.githubusercontent.com/alchemydc/zcash-vote-server/main/infrastructure/common/scripts/install-cometbft.sh
curl -O https://raw.githubusercontent.com/alchemydc/zcash-vote-server/main/infrastructure/common/scripts/build-vote-server.sh

sudo bash install-base.sh
sudo bash install-cometbft.sh
sudo bash build-vote-server.sh
```

### 3. Configure and Start Services
Follow the post-deployment instructions as documented in the GCP guide.

## Backup and Recovery

### Proxmox Built-in Backup
```bash
# Create backup
vzdump <VMID> --storage local --mode snapshot --compress zstd

# Restore from backup
qmrestore /var/lib/vz/dump/vzdump-qemu-<VMID>-*.vma.zst <NEW_VMID>
```

### Data-Level Backup
```bash
# On the VM
sudo systemctl stop zcash-vote-server
sudo systemctl stop cometbft
sudo tar -czf /tmp/validator-backup.tar.gz /opt/zcash-vote
# Copy backup off-site
```

## High Availability Considerations

For production deployments, consider:

### Proxmox Cluster
- 3+ Proxmox nodes for quorum
- Shared storage (Ceph, NFS, or other)
- HA groups for automatic failover

### Validator HA
- Multiple validators across different Proxmox hosts
- Geographic distribution if possible
- Coordinated genesis configuration
- Network redundancy

## Cost Comparison

### Hardware Investment (One-time)
- Entry Server: $1,000-2,000
  - Can run 4-8 validators
  - Break-even vs cloud: 12-24 months
- Enterprise Server: $5,000-10,000
  - Can run 20+ validators
  - Break-even vs cloud: 24-36 months

### Ongoing Costs
- Power: ~$20-100/month (depending on hardware)
- Network: $50-200/month (business internet)
- **Total: ~$70-300/month for multiple validators**

Compare to:
- GCP: ~$72/month per validator
- AWS: ~$42/month per validator
- DO: ~$34/month per validator

**Break-even**: 2-3 validators makes self-hosting cost-competitive

## Contributing

We welcome contributions for Proxmox support! Priority areas:

1. **Terraform Configuration** - Telmate provider implementation
2. **Template Automation** - Scripts to build Ubuntu template
3. **Network Configuration** - Complex setups (VLANs, bridges)
4. **HA Configuration** - Multi-node cluster support
5. **Documentation** - Setup guides and best practices

See the GCP implementation in `../gcp/` as a reference.

## Resources

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Terraform Proxmox Provider (Telmate)](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)

## Support

For Proxmox-specific questions:
- Proxmox Forum: https://forum.proxmox.com/
- Infrastructure issues: File issue in this repository
- zcash-vote-server: https://github.com/alchemydc/zcash-vote-server/issues
