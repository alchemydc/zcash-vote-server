# zcash-vote-server Infrastructure

Infrastructure as Code for deploying zcash-vote-server validator nodes across multiple self hosted, bare metal, VPS or cloud providers.

## Overview

This infrastructure supports deploying production-grade validator nodes that participate in the zcash-vote-server consensus network. The implementation uses OpenTofu (Terraform) for infrastructure provisioning and includes common installation scripts that work across cloud providers.

## Architecture

```
infrastructure/
├── common/             # Shared scripts and modules
│   ├── scripts/        # Installation and setup scripts
│   └── modules/        # Reusable infrastructure modules (future)
├── gcp/                # Google Cloud Platform (✅ Available)
├── aws/                # Amazon Web Services (🚧 Planned)
├── digitalocean/       # DigitalOcean (🚧 Planned)
└── proxmox/            # Proxmox VE (🚧 Planned)
```

## Supported Cloud Providers

### ✅ Google Cloud Platform (GCP)
Full OpenTofu implementation available. See [gcp/README.md](gcp/README.md) for details.

**Features:**
- Automated VM provisioning
- Network security (firewall rules)
- Service account with minimal permissions
- Cloud monitoring and logging
- Automatic snapshots
- Production-ready configuration

**Quick Start:**
```bash
cd gcp
cp gcloud.env.example gcloud.env
# Edit gcloud.env with your values
source gcloud.env
tofu init
tofu apply
```

### 🚧 AWS (Coming Soon)
Planned support for Amazon Web Services. See [aws/README.md](aws/README.md).

### 🚧 DigitalOcean (Coming Soon)
Planned support for DigitalOcean. See [digitalocean/README.md](digitalocean/README.md).

### 🚧 Proxmox VE (Coming Soon)
Planned support for Proxmox Virtual Environment for self-hosted/bare-metal deployments. See [proxmox/README.md](proxmox/README.md).

## Common Scripts

The `common/scripts/` directory contains cloud-agnostic installation scripts:

- **install-base.sh** - Base system setup (dependencies, Rust, firewall)
- **install-cometbft.sh** - CometBFT consensus engine installation
- **build-vote-server.sh** - Build zcash-vote-server from source

These scripts can be used independently for manual deployments on any Ubuntu 22.04 system.

## Deployment Models

### Production Single Validator
Each deployment creates one validator node that joins an existing validator network.

**Requirements:**
- Coordination with other validators for genesis file
- Exchange of peer node IDs and addresses
- Minimum 4 validators total in network for production
- 2/3 Byzantine fault tolerance

### Network Topology
```
        Validator 1          Validator 2
            |                     |
            +-----CometBFT P2P----+
            |                     |
        Validator 3          Validator 4
```

## Security Considerations

### Network Security
- **SSH**: Restricted to admin IP ranges
- **CometBFT P2P (26656)**: Open to validator network
- **API (8000)**: Internal only by default (configurable)
- **ABCI (26658)**: Localhost only

### Secrets Management
- SSH keys managed via cloud provider metadata
- Validator private keys generated on instance
- No secrets stored in infrastructure code
- Use `.gitignore` to prevent accidental commits

### Best Practices
1. Use separate service accounts with minimal permissions
2. Enable cloud provider logging and monitoring
3. Configure automatic backups/snapshots
4. Restrict API access to known IP ranges
5. Keep software updated regularly

## Post-Deployment Configuration

After infrastructure provisioning, manual configuration is required:

1. **Genesis File**: Coordinate with other validators
2. **Persistent Peers**: Exchange node IDs and addresses
3. **Service Startup**: Manually start services after configuration
4. **Verification**: Check sync status and block production

Detailed instructions are provided on each deployed instance at `/opt/zcash-vote/POST_DEPLOYMENT.md`.

## Monitoring and Logging

### On-Instance Logs
```bash
# Service logs
sudo journalctl -u cometbft -f
sudo journalctl -u zcash-vote-server -f

# Installation logs
sudo journalctl -u google-startup-scripts -f  # GCP
cat /var/log/zcash-vote-setup.log
```

### Cloud Provider Integration
- GCP: Cloud Logging and Cloud Monitoring enabled
- AWS: CloudWatch integration (planned)
- DigitalOcean: Native monitoring (planned)

## Backup and Recovery

### Automatic Backups
- Disk snapshots scheduled automatically
- Retention: 7 days by default (configurable)
- Snapshots include full validator state

### Manual Backup
```bash
# On instance
sudo systemctl stop zcash-vote-server
sudo systemctl stop cometbft
tar -czf backup.tar.gz /opt/zcash-vote
```

### Recovery
Restore from snapshot or:
1. Deploy new instance
2. Stop services
3. Restore data directories
4. Start services

## Maintenance

### Software Updates

**zcash-vote-server:**
```bash
cd /opt/zcash-vote/zcash-vote-server
sudo -u zcash-vote git pull
sudo -u zcash-vote cargo build --release
sudo systemctl restart zcash-vote-server
```

**CometBFT:**
Download new version manually and replace binary.

### Validator Key Rotation
Coordinate with other validators to update genesis file with new keys.

## Cost Estimates

### GCP (us-central1)
- e2-standard-2: ~$48/month
- 100GB SSD disk: ~$17/month
- Static IP: ~$7/month
- **Total: ~$72/month per validator**

### AWS (Planned)
- t3.medium: ~$30/month
- 100GB gp3: ~$8/month
- Elastic IP: ~$3.65/month
- **Estimated: ~$42/month per validator**

### DigitalOcean (Planned)
- Standard Droplet 4GB: $24/month
- 100GB Volume: $10/month
- **Estimated: ~$34/month per validator**

*Prices are estimates and exclude data transfer costs.*

## Troubleshooting

### Common Issues

**"Services won't start"**
- Check genesis.json is configured
- Verify persistent_peers is set
- Check logs: `sudo journalctl -u cometbft -n 100`

**"Not syncing blocks"**
- Verify network connectivity (port 26656)
- Check that 2/3 of validators are online
- Ensure genesis matches other validators

**"Can't SSH to instance"**
- Verify your IP in admin_ip_ranges
- Check cloud firewall rules
- Try cloud provider CLI (gcloud compute ssh, etc.)

### Local node debugging

Ensure `jq` is installed (`sudo apt install jq` or `brew install jq`).

Useful quick checks (these query the local CometBFT RPC on the default port 26657 and pretty-print results with `jq`):

- Show node info (id, moniker, version, etc.)
```bash
curl -s "http://localhost:26657/status" | jq .result.node_info
```

- List validator addresses known to this node
```bash
curl -s "http://localhost:26657/validators" | jq .result.validators[].address
```

- List peer monikers (human-readable peer names)
```bash
curl -s "http://localhost:26657/net_info" | jq .result.peers[].node_info.moniker
```

- List peer remote IPs (useful for connectivity checks)
```bash
curl -s "http://localhost:26657/net_info" | jq .result.peers[].remote_ip
```

- Show ABCI application information (verifies ABCI connection to zcash-vote-server)
```bash
curl -s "http://localhost:26657/abci_info" | jq
```

Notes:
- These assume the node RPC is available on localhost:26657. If your node uses a different host/port, adjust the URL accordingly.
- `abci_info` confirms the application is connected and responding; `status` shows sync/chain state.
- If a command fails, check logs:
```bash
sudo journalctl -u cometbft -n 200
sudo journalctl -u zcash-vote-server -n 200
```

### Getting Help

For infrastructure issues:
- Check cloud provider documentation
- Review OpenTofu error messages
- File issue in this repository

For zcash-vote-server issues:
- See application logs
- Check https://github.com/alchemydc/zcash-vote-server

## Contributing

Contributions welcome! Priority areas:

1. **AWS Implementation** - EC2, VPC, security groups
2. **DigitalOcean Implementation** - Droplets, networking
3. **Ansible Playbooks** - Configuration management
4. **Monitoring Dashboards** - Grafana, Prometheus
5. **Documentation** - Improvements and clarifications

See individual cloud provider directories for implementation examples.

## License

Same as parent project. See LICENSE file in repository root.

## Support

- Documentation: This README and provider-specific READMEs
- Issues: in GitHub repository
- Community: [Zcash community forums](https://forum.zcashcommunity.com/)
