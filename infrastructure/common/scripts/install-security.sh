#!/bin/bash
set -euo pipefail

# install-security.sh
# Security hardening script for zcash-vote-server validator nodes
# - Hardens SSH configuration (key-based auth only)
# - Installs and configures fail2ban for brute force protection
# Compatible with Ubuntu 22.04 LTS

echo "===================================="
echo "Security Hardening Setup"
echo "===================================="

# Backup existing SSH configuration
echo "[1/4] Backing up SSH configuration..."
if [ ! -f /etc/ssh/sshd_config.backup ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    echo "SSH config backed up to /etc/ssh/sshd_config.backup"
else
    echo "Backup already exists, skipping..."
fi

# Harden SSH configuration
echo "[2/4] Hardening SSH configuration..."
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'SSHCONFIG'
# SSH Hardening Configuration for zcash-vote-server
# Disable password authentication - use keys only
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM no

# Public key authentication only
PubkeyAuthentication yes

# Disable root login
PermitRootLogin no

# Disable empty passwords
PermitEmptyPasswords no

# Limit authentication attempts
# Set to 6 to accommodate SSH agents with multiple keys
MaxAuthTries 6
MaxSessions 2

# Reduce login grace time
LoginGraceTime 20

# Use strong ciphers and MACs
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Disable X11 forwarding
X11Forwarding no

# Disable TCP forwarding
AllowTcpForwarding no

# Disable agent forwarding
AllowAgentForwarding no

# Log more information
LogLevel VERBOSE

# Strict mode on home directories and key files
StrictModes yes
SSHCONFIG

echo "SSH hardening configuration applied"

# Install fail2ban
echo "[3/4] Installing fail2ban..."
if ! command -v fail2ban-client &> /dev/null; then
    apt-get update
    apt-get install -y fail2ban
    echo "fail2ban installed"
else
    echo "fail2ban already installed, skipping..."
fi

# Configure fail2ban
echo "[4/4] Configuring fail2ban..."
cat > /etc/fail2ban/jail.local <<'FAIL2BANCONFIG'
[DEFAULT]
# Ban hosts for 1 hour (3600 seconds)
bantime = 3600

# A host is banned if it generates 3 failures in 10 minutes
findtime = 600
maxretry = 3

# Destination email for alerts (optional - configure if needed)
# destemail = admin@example.com
# sendername = Fail2Ban
# action = %(action_mwl)s

# Use iptables for banning (works with ufw)
banaction = iptables-multiport
banaction_allports = iptables-allports

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 3600

# More aggressive settings for repeat offenders
[sshd-aggressive]
enabled = false
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 2
findtime = 3600
bantime = 86400
FAIL2BANCONFIG

echo "fail2ban configuration applied"

# Enable and start fail2ban
echo "Enabling fail2ban service..."
systemctl enable fail2ban
systemctl restart fail2ban

# Wait for fail2ban to fully initialize (socket creation)
echo "Waiting for fail2ban to initialize..."
sleep 3

# Validate SSH configuration before restarting
echo "Validating SSH configuration..."
if sshd -t; then
    echo "SSH configuration is valid"
    systemctl restart sshd
    echo "SSH service restarted with hardened configuration"
else
    echo "ERROR: SSH configuration validation failed!"
    echo "Restoring backup configuration..."
    cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
    rm /etc/ssh/sshd_config.d/99-hardening.conf
    systemctl restart sshd
    exit 1
fi

# Display fail2ban status (non-fatal if it fails)
echo ""
echo "===================================="
echo "Security Hardening Complete!"
echo "===================================="
echo ""
echo "SSH Configuration:"
echo "  - Password authentication: DISABLED"
echo "  - Key-based authentication: ENABLED"
echo "  - Root login: DISABLED"
echo "  - Max auth tries: 6"
echo ""
echo "fail2ban Status:"
fail2ban-client status || echo "fail2ban is starting up (status check will be available shortly)"
echo ""
echo "fail2ban SSH Jail:"
fail2ban-client status sshd || echo "SSH jail will activate on first SSH activity"
echo ""
echo "IMPORTANT: Ensure you can connect via SSH key before closing this session!"
echo "Backup config available at: /etc/ssh/sshd_config.backup"
echo ""
echo "To check banned IPs: sudo fail2ban-client status sshd"
echo "To unban an IP: sudo fail2ban-client set sshd unbanip <IP>"
echo "===================================="
