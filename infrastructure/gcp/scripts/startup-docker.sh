#!/bin/bash
set -euo pipefail

# GCP Startup Script for zcash-vote-server validator node (Docker/Binary version)
# This script runs on first boot to set up the validator environment

LOGFILE="/var/log/zcash-vote-setup.log"

# Redirect all output to log file
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "=========================================="
echo "Zcash Vote Server Setup (Docker) - $(date)"
echo "=========================================="
echo "Validator: ${validator_name}"
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
echo "[Phase 1] Installing Google Cloud Ops Agent..."
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

# Install Docker Engine
echo "[Phase 2] Installing Docker Engine..."
if ! command -v docker &> /dev/null; then
    # Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add the repository to Apt sources:
    echo \
      "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update

    # Install Docker packages
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    echo "Docker installed successfully"
else
    echo "Docker already installed"
fi

# Create zcash-vote user and group
echo "[Phase 3] Configuring user environment..."
if ! id "zcash-vote" &>/dev/null; then
    useradd -m -s /bin/bash zcash-vote
    echo "Created zcash-vote user"
fi

# Add zcash-vote to docker group
usermod -aG docker zcash-vote
echo "Added zcash-vote to docker group"

# Download setup client
echo "[Phase 4] Downloading setup client..."
SETUP_URL="https://github.com/hhanh00/zcash-vote-setup/releases/latest/download/client-x86_64"
CLIENT_PATH="/home/zcash-vote/client-x86_64"

# Use runuser to download as zcash-vote to ownership is correct by default, 
# but curl output writes to file which needs write permission. 
# Simpler to download as root then chown.
curl -fsSL "$SETUP_URL" -o "$CLIENT_PATH"
chmod +x "$CLIENT_PATH"
chown zcash-vote:zcash-vote "$CLIENT_PATH"

echo "Setup client downloaded to $CLIENT_PATH"

echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Installation successful."
echo "You must now log in and run the setup client manually."
echo ""
echo "Command to run:"
echo "  sudo su - zcash-vote"
echo "  ./client-x86_64 \$COORDINATOR_IP:\$COORDINATOR_PORT <your-node-name>"
echo ""
echo "=========================================="
