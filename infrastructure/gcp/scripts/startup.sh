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
echo "CometBFT P2P Port: ${cometbft_p2p_port}"
echo "Repository: ${vote_server_repo}"
echo "Branch: ${vote_server_branch}"
echo "=========================================="

# Configure GNU Screen early so admins have function-key bindings during setup
echo "[Setup] Configuring GNU Screen system-wide..."
cat > /etc/screenrc <<'SCREENRC'
# Function key bindings for screen window navigation
bindkey -k k1 select 0  #  F1 = screen 0
bindkey -k k2 select 1  #  F2 = screen 1
bindkey -k k3 select 2  #  F3 = screen 2
bindkey -k k4 select 3  #  F4 = screen 3
bindkey -k k5 select 4  #  F5 = screen 4
bindkey -k k6 select 5  #  F6 = screen 5
bindkey -k k7 select 6  #  F7 = screen 6
bindkey -k k8 select 7  #  F8 = screen 7
bindkey -k k9 select 8  #  F9 = screen 8
bindkey -k k10 select 9 #  F10 = screen 9
bindkey -k F1 prev      # F11 = prev
bindkey -k F2 next      # F12 = next
SCREENRC
chmod 644 /etc/screenrc || true
echo "GNU Screen configured (system /etc/screenrc written)"

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
curl -fsSL https://raw.githubusercontent.com/alchemydc/zcash-vote-server/${vote_server_branch}/infrastructure/common/scripts/install-security.sh -o install-security.sh
curl -fsSL https://raw.githubusercontent.com/alchemydc/zcash-vote-server/${vote_server_branch}/infrastructure/common/scripts/install-cometbft.sh -o install-cometbft.sh
curl -fsSL https://raw.githubusercontent.com/alchemydc/zcash-vote-server/${vote_server_branch}/infrastructure/common/scripts/build-vote-server.sh -o build-vote-server.sh

# Get systemd service files
mkdir -p systemd
curl -fsSL https://raw.githubusercontent.com/alchemydc/zcash-vote-server/${vote_server_branch}/infrastructure/common/scripts/systemd/cometbft.service -o systemd/cometbft.service
curl -fsSL https://raw.githubusercontent.com/alchemydc/zcash-vote-server/${vote_server_branch}/infrastructure/common/scripts/systemd/zcash-vote-server.service -o systemd/zcash-vote-server.service

chmod +x *.sh

# Conditionally run security hardening based on instance metadata
echo "[Phase 1.5/7] Checking remote SSH metadata flag..."
REMOTE_SSH_ENABLED=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/remote-ssh-enabled" || echo "false")

if [ "$${REMOTE_SSH_ENABLED,,}" = "true" ]; then
  echo "Remote SSH enabled: running install-security.sh"
  # install-security.sh is idempotent; run after base scripts are present
  bash install-security.sh || echo "install-security.sh failed (non-fatal) and will not block setup"
else
  echo "Remote SSH disabled: skipping install-security.sh (use gcloud compute ssh to access the instance)"
fi

# Run base installation
echo "[Phase 2/8] Installing base system..."
bash install-base.sh

%{ if enable_tailscale }
echo "[Phase 2.5/8] Installing and configuring Tailscale..."
export TAILSCALE_AUTH_KEY="${tailscale_auth_key}"
export TAILSCALE_TAILNET="${tailscale_tailnet}"
export TAILSCALE_TAGS="${tailscale_tags}"
bash install-tailscale.sh

# Get Tailscale IP for CometBFT binding (may be empty on failure)
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
echo "Tailscale IP assigned: $${TAILSCALE_IP}"
export COMETBFT_BIND_IP="$${TAILSCALE_IP}"
%{ else }
export COMETBFT_BIND_IP="0.0.0.0"
%{ endif }

# Install CometBFT
echo "[Phase 3/8] Installing CometBFT..."
export COMETBFT_VERSION="${cometbft_version}"
export COMETBFT_P2P_PORT="${cometbft_p2p_port}"
bash install-cometbft.sh

# Build zcash-vote-server
echo "[Phase 4/7] Building zcash-vote-server..."
export VOTE_SERVER_REPO="${vote_server_repo}"
export VOTE_SERVER_BRANCH="${vote_server_branch}"
bash build-vote-server.sh

# Initialize CometBFT as zcash-vote user
echo "[Phase 5/8] Initializing CometBFT..."
sudo -u zcash-vote bash -c "cometbft init --home /opt/zcash-vote/.cometbft"

# Configure CometBFT binding and/or custom P2P port
COMET_PORT="${cometbft_p2p_port}"
if [ -n "$${COMETBFT_BIND_IP}" ] && [ "$${COMETBFT_BIND_IP}" != "0.0.0.0" ]; then
  echo "Configuring CometBFT to bind to $${COMETBFT_BIND_IP}:$${COMET_PORT} in config.toml..."
  sudo -u zcash-vote sed -i "s|laddr = \"tcp://0.0.0.0:26656\"|laddr = \"tcp://$${COMETBFT_BIND_IP}:$${COMET_PORT}\"|" /opt/zcash-vote/.cometbft/config/config.toml || echo "Warning: failed to update laddr in config.toml"
else
  if [ "$${COMET_PORT}" != "26656" ]; then
    echo "Configuring CometBFT P2P port to $${COMET_PORT} in config.toml..."
    sudo -u zcash-vote sed -i "s|laddr = \"tcp://0.0.0.0:26656\"|laddr = \"tcp://0.0.0.0:$${COMET_PORT}\"|" /opt/zcash-vote/.cometbft/config/config.toml || echo "Warning: failed to update laddr in config.toml"
  fi
fi

# Get the node ID for peer configuration
NODE_ID=$(sudo -u zcash-vote cometbft show-node-id --home /opt/zcash-vote/.cometbft)
echo "Node ID: $NODE_ID"

# Display key backup instructions and public key info (safe to log)
VALIDATOR_ADDRESS=$(sudo -u zcash-vote cometbft show-address --home /opt/zcash-vote/.cometbft || true)
VALIDATOR_PUBKEY=$(sudo -u zcash-vote jq -r '.pub_key.value' /opt/zcash-vote/.cometbft/config/priv_validator_key.json 2>/dev/null || echo "N/A")
NODE_KEY_ID=$(sudo -u zcash-vote jq -r '.id' /opt/zcash-vote/.cometbft/config/node_key.json 2>/dev/null || echo "N/A")

echo "=========================================="
echo "IMPORTANT: BACKUP KEYS NOW"
echo "=========================================="
echo "Validator Address: $${VALIDATOR_ADDRESS}"
echo "Validator PubKey: $${VALIDATOR_PUBKEY}"
echo "Node Key ID: $${NODE_KEY_ID}"
echo ""
echo "Critical files to backup (on the instance):"
echo "  - /opt/zcash-vote/.cometbft/config/priv_validator_key.json"
echo "  - /opt/zcash-vote/.cometbft/config/node_key.json"
echo ""
echo "You can retrieve these with the Terraform output commands or via SSH:"
echo "  - Terraform: tofu output -raw backup_validator_key_command"
echo "  - SSH: Run the exact command returned by: tofu output -raw ssh_command"
echo "    (that value will include --tunnel-through-iap when SSH is not exposed publicly)"
echo "=========================================="

# Install systemd services
echo "[Phase 6/7] Installing systemd services..."
cp systemd/cometbft.service /etc/systemd/system/
cp systemd/zcash-vote-server.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable cometbft
systemctl enable zcash-vote-server

# Configure additional firewall rules if API access is enabled
echo "[Phase 7/8] Final configuration..."
%{ if enable_api_access }
echo "Configuring API firewall access..."
ufw allow 8000/tcp comment 'zcash-vote-server API'
%{ endif }

%{ if enable_tailscale }
echo "Configuring CometBFT P2P firewall for Tailscale only..."
# Allow P2P port only from Tailscale subnet (RFC6598 / 100.64.0.0/10)
ufw allow from 100.64.0.0/10 to any port ${cometbft_p2p_port} proto tcp comment 'CometBFT P2P (Tailscale)'
%{ else }
echo "Configuring CometBFT P2P firewall..."
ufw allow ${cometbft_p2p_port}/tcp comment 'CometBFT P2P'
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
# persistent_peers = "node_id1@ip1:${cometbft_p2p_port},node_id2@ip2:${cometbft_p2p_port},node_id3@ip3:${cometbft_p2p_port}"
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
- Verify network connectivity to peers (port ${cometbft_p2p_port})
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
