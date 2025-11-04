#!/bin/bash
set -euo pipefail

# install-tailscale.sh
# Install and configure Tailscale with headless authentication
# Designed for Ubuntu 22.04 (jammy)

TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
TAILSCALE_TAILNET="${TAILSCALE_TAILNET:-}"
TAILSCALE_TAGS="${TAILSCALE_TAGS:-}"

echo "===================================="
echo "Tailscale Installation"
echo "===================================="

if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    echo "Error: TAILSCALE_AUTH_KEY not provided"
    exit 1
fi

# Install prerequisites (curl/apt-transport already expected from install-base.sh)
echo "[1/5] Adding Tailscale repository and key..."
# Download the Tailscale archive key into a dedicated keyring (modern APT usage)
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | \
    tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null 2>&1 || true

# Create an explicit sources.list entry that references the keyring via signed-by
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu jammy main" | \
    tee /etc/apt/sources.list.d/tailscale.list >/dev/null 2>&1

echo "[2/5] Installing Tailscale..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tailscale

# Basic kernel networking config (allow forwarding if needed)
echo "[3/5] Configuring kernel parameters..."
{
  echo 'net.ipv4.ip_forward = 1'
  echo 'net.ipv6.conf.all.forwarding = 1'
} >> /etc/sysctl.d/99-tailscale.conf || true
sysctl -p /etc/sysctl.d/99-tailscale.conf >/dev/null 2>&1 || true

# Authenticate using the provided auth key
echo "[4/5] Connecting to Tailscale network (headless auth)..."
# Use tailscaled if available
if ! systemctl is-active --quiet tailscaled; then
  systemctl enable --now tailscaled || true
fi

# Run tailscale up with provided key and tags
# Note: --accept-routes and --ssh are optional; operators can adjust as needed
TAGS_ARG=""
if [ -n "$TAILSCALE_TAGS" ]; then
  TAGS_ARG="--advertise-tags=${TAILSCALE_TAGS}"
fi

# If tailnet is provided, it's informational; auth key already scopes the device.
tailscale up --authkey="${TAILSCALE_AUTH_KEY}" ${TAGS_ARG} --hostname="${HOSTNAME:-validator}" --accept-routes --ssh || {
    echo "Warning: tailscale up failed; will attempt to continue"
}

# Wait for Tailscale to be ready and get IP
echo "[5/5] Waiting for Tailscale to report an IP..."
for i in $(seq 1 30); do
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
    if [ -n "$TAILSCALE_IP" ]; then
        break
    fi
    sleep 1
done

if [ -n "$TAILSCALE_IP" ]; then
    echo "✓ Tailscale connected successfully"
    echo "  Tailscale IP: ${TAILSCALE_IP}"
else
    echo "Warning: Tailscale did not report an IP address after timeout"
fi

# Output status for logs
tailscale status || true

echo "===================================="
echo "Tailscale installation complete!"
echo "===================================="
