#!/bin/bash
set -euo pipefail

# GCP Startup Script for zcash-vote-server validator node
# This script runs on first boot to set up the validator

LOGFILE="/var/log/zcash-vote-setup.log"
SCRIPTS_DIR="/opt/zcash-vote-scripts"

# Redirect all output to log file
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "=========================================="
echo "Zcash Vote Server Setup - $(date)"
echo "=========================================="
echo "Validator: ${validator_name}"
echo "CometBFT Version: ${cometbft_version}"
echo "Repository: ${vote_server_repo}"
echo "Branch: ${vote_server_branch}"
echo "=========================================="

# Install Google Cloud Ops Agent for log forwarding to Cloud Logging
echo "[Phase 0/7] Installing Google Cloud Ops Agent..."
if ! systemctl is-active --quiet google-cloud-ops-agent; then
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    bash add-google-cloud-ops-agent-repo.sh --also-install
    
    # Configure to collect our custom log file
    cat > /etc/google-cloud-ops-agent/config.yaml <<'OPSCONFIG'
logging:
  receivers:
    zcash_vote_setup:
      type: files
      include_paths:
        - /var/log/zcash-vote-setup.log
  service:
    pipelines:
      default_pipeline:
        receivers: [syslog, zcash_vote_setup]
OPSCONFIG
    
    systemctl restart google-cloud-ops-agent
    echo "Ops Agent installed and configured"
else
    echo "Ops Agent already running, skipping..."
fi

# Download setup scripts from repository
echo "[Phase 1/7] Downloading setup scripts..."
mkdir -p "$SCRIPTS_DIR"
cd "$SCRIPTS_DIR"

# Get the common scripts directly from the repository
curl -fsSL https://raw.githubusercontent.com/alchemydc/zcash-vote-server/${vote_server_branch}/infrastructure/common/scripts/install-base.sh -o install-base.sh
curl -fsSL https://raw.githubusercontent.com/alchemydc/zcash-vote-server/${vote_server_branch}/infrastructure/common/scripts/install-cometbft.sh -o install-cometbft.sh
curl -fsSL https://raw.githubusercontent.com/alchemydc/zcash-vote-server/${vote_server_branch}/infrastructure/common/scripts/build-vote-server.sh -o build-vote-server.sh

# Get systemd service files
mkdir -p systemd
curl -fsSL https://raw.githubusercontent.com/alchemydc/zcash-vote-server/${vote_server_branch}/infrastructure/common/scripts/systemd/cometbft.service -o systemd/cometbft.service
curl -fsSL https://raw.githubusercontent.com/alchemydc/zcash-vote-server/${vote_server_branch}/infrastructure/common/scripts/systemd/zcash-vote-server.service -o systemd/zcash-vote-server.service

chmod +x *.sh

# Run base installation
echo "[Phase 2/7] Installing base system..."
bash install-base.sh

# Install CometBFT
echo "[Phase 3/7] Installing CometBFT..."
export COMETBFT_VERSION="${cometbft_version}"
bash install-cometbft.sh

# Build zcash-vote-server
echo "[Phase 4/7] Building zcash-vote-server..."
export VOTE_SERVER_REPO="${vote_server_repo}"
export VOTE_SERVER_BRANCH="${vote_server_branch}"
bash build-vote-server.sh

# Initialize CometBFT as zcash-vote user
echo "[Phase 5/7] Initializing CometBFT..."
sudo -u zcash-vote bash -c "cometbft init --home /opt/zcash-vote/.cometbft"

# Get the node ID for peer configuration
NODE_ID=$(sudo -u zcash-vote cometbft show-node-id --home /opt/zcash-vote/.cometbft)
echo "Node ID: $NODE_ID"

# Install systemd services
echo "[Phase 6/7] Installing systemd services..."
cp systemd/cometbft.service /etc/systemd/system/
cp systemd/zcash-vote-server.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable cometbft
systemctl enable zcash-vote-server

# Configure additional firewall rules if API access is enabled
echo "[Phase 7/7] Final configuration..."
%{ if enable_api_access }
echo "Configuring API firewall access..."
ufw allow 8000/tcp comment 'zcash-vote-server API'
%{ endif }

# Create a helpful README for the operator
cat > /opt/zcash-vote/POST_DEPLOYMENT.md <<'POSTDEPLOY'
# Post-Deployment Configuration

## Installation Complete!

The validator node software is installed but services are NOT running yet.
This is intentional - you must configure the genesis file and peers first.

## Next Steps

### 1. Configure Genesis File

Coordinate with other validators to obtain the `genesis.json` file.

```bash
# Copy genesis file to CometBFT config directory
sudo -u zcash-vote cp genesis.json /opt/zcash-vote/.cometbft/config/
```

### 2. Configure Persistent Peers

Get peer information from other validators and update the config:

```bash
# Edit config file
sudo -u zcash-vote nano /opt/zcash-vote/.cometbft/config/config.toml

# Find the persistent_peers line and add other validators:
# persistent_peers = "node_id1@ip1:26656,node_id2@ip2:26656,node_id3@ip3:26656"
```

Your node ID for sharing with other validators:
```
$${NODE_ID}
```

### 3. Start Services

Once configuration is complete:

```bash
# Start CometBFT
sudo systemctl start cometbft

# Wait a few seconds, then start the vote server
sudo systemctl start zcash-vote-server
```

### 4. Verify Operation

```bash
# Check service status
sudo systemctl status cometbft
sudo systemctl status zcash-vote-server

# View logs
sudo journalctl -u cometbft -f
sudo journalctl -u zcash-vote-server -f

# Check block height (should increase)
curl localhost:26657/status | jq .result.sync_info.latest_block_height
```

## File Locations

- Application: `/opt/zcash-vote/zcash-vote-server/`
- Configuration: `/opt/zcash-vote/config/Rocket.toml`
- CometBFT config: `/opt/zcash-vote/.cometbft/config/`
- Database: `/opt/zcash-vote/vote.db`
- Election data: `/opt/zcash-vote/data/`

## Troubleshooting

### Services won't start
- Check that genesis.json is in place
- Verify persistent_peers is configured
- Check logs: `sudo journalctl -u cometbft -n 100`

### Not syncing blocks
- Verify network connectivity to peers (port 26656)
- Check peer addresses are correct
- Ensure at least 2/3 of validators are online

### API not accessible
- Check firewall: `sudo ufw status`
- Verify service is running: `systemctl status zcash-vote-server`
- Check API logs: `sudo journalctl -u zcash-vote-server -f`

## Service Management

```bash
# Start services
sudo systemctl start cometbft
sudo systemctl start zcash-vote-server

# Stop services
sudo systemctl stop zcash-vote-server
sudo systemctl stop cometbft

# Restart services
sudo systemctl restart cometbft
sudo systemctl restart zcash-vote-server

# View logs
sudo journalctl -u cometbft -f
sudo journalctl -u zcash-vote-server -f
```
POSTDEPLOY

chown zcash-vote:zcash-vote /opt/zcash-vote/POST_DEPLOYMENT.md

echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Installation successful. Services are installed but NOT running."
echo ""
echo "Next steps:"
echo "1. Configure genesis file and persistent peers"
echo "2. Start services manually"
echo ""
echo "See /opt/zcash-vote/POST_DEPLOYMENT.md for detailed instructions"
echo ""
echo "Your Node ID: $NODE_ID"
echo "=========================================="
