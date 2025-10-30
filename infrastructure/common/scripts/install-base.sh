#!/bin/bash
set -euo pipefail

# Set HOME explicitly when running as root (startup script context)
export HOME=/root

# install-base.sh
# Common base system setup for zcash-vote-server validator node
# Compatible with Ubuntu 22.04 LTS

echo "===================================="
echo "Base System Setup"
echo "===================================="

# Update package lists
echo "[1/5] Updating package lists..."
apt-get update

# Install build essentials and dependencies
echo "[2/5] Installing build dependencies..."
apt-get install -y \
    build-essential \
    libssl-dev \
    pkg-config \
    curl \
    git \
    jq \
    sqlite3 \
    ufw

# Install Rust toolchain
echo "[3/5] Installing Rust toolchain..."
if ! command -v rustc &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    source "$HOME/.cargo/env"
    # Add cargo to system-wide path
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> /etc/profile.d/rust.sh
else
    echo "Rust already installed, skipping..."
fi

# Configure firewall (UFW)
echo "[4/5] Configuring firewall..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 26656/tcp comment 'CometBFT P2P'
# show the rules after configuration
ufw status verbose
# Note: Additional firewall rules will be configured based on deployment needs

# Create application user
echo "[5/6] Creating application user..."
if ! id -u zcash-vote &> /dev/null; then
    useradd -r -m -s /bin/bash -d /opt/zcash-vote zcash-vote
    echo "User 'zcash-vote' created"
else
    echo "User 'zcash-vote' already exists, skipping..."
fi

# Run security hardening (if script exists)
echo "[6/6] Running security hardening..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/install-security.sh" ]; then
    bash "$SCRIPT_DIR/install-security.sh"
else
    echo "Security script not found at $SCRIPT_DIR/install-security.sh"
    echo "Skipping security hardening - install manually if needed"
fi

echo "===================================="
echo "Base system setup complete!"
echo "===================================="
