# Security Hardening Guide

This document describes the security measures implemented in the zcash-vote-server infrastructure and how to manage them.

## Overview

The infrastructure includes multiple layers of security protection:

1. **SSH Hardening** - Key-based authentication only, no passwords
2. **fail2ban** - Automatic IP banning for brute force attacks
3. **UFW Firewall** - Network access control
4. **Minimal Service Account Permissions** - Least privilege principle

## Automatic Security Hardening

### What Gets Configured

During deployment, the `install-security.sh` script automatically:

1. **Disables Password Authentication**
   - SSH key-based authentication only
   - No password logins accepted
   - Challenge-response authentication disabled

2. **Hardens SSH Configuration**
   - Root login disabled
   - Maximum 6 authentication attempts (accommodates multiple SSH keys)
   - 20-second login grace time
   - Strong ciphers and MACs only
   - X11 forwarding disabled
   - TCP/Agent forwarding disabled
   - PAM enabled (required for GCP SSH key injection from metadata)

3. **Installs fail2ban**
   - Monitors SSH authentication attempts
   - Bans IPs after 3 failed attempts in 10 minutes
   - 1-hour ban duration (configurable)
   - Automatic unbanning after timeout

4. **Creates Configuration Backups**
   - Original SSH config saved to `/etc/ssh/sshd_config.backup`
   - Automatic rollback on validation failure

## SSH Configuration Details

### Location
- Main hardening config: `/etc/ssh/sshd_config.d/99-hardening.conf`
- Backup of original: `/etc/ssh/sshd_config.backup`

### Key Settings
```
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
MaxAuthTries 6
MaxSessions 2
LoginGraceTime 20
```

### Allowed Ciphers
- chacha20-poly1305@openssh.com
- aes256-gcm@openssh.com
- aes128-gcm@openssh.com
- aes256-ctr, aes192-ctr, aes128-ctr

## fail2ban Configuration

### Default Settings
- **Ban after**: 3 failed attempts
- **Time window**: 10 minutes (600 seconds)
- **Ban duration**: 1 hour (3600 seconds)
- **Log file**: `/var/log/auth.log`

### Configuration Files
- Main config: `/etc/fail2ban/jail.local`
- Logs: `/var/log/fail2ban.log`

### Monitoring Commands

Check fail2ban status:
```bash
sudo fail2ban-client status
```

Check SSH jail status:
```bash
sudo fail2ban-client status sshd
```

View currently banned IPs:
```bash
sudo fail2ban-client status sshd | grep "Banned IP list"
```

### Managing Banned IPs

Unban a specific IP:
```bash
sudo fail2ban-client set sshd unbanip <IP_ADDRESS>
```

Unban all IPs:
```bash
sudo fail2ban-client unban --all
```

Ban an IP manually:
```bash
sudo fail2ban-client set sshd banip <IP_ADDRESS>
```

### Viewing Logs

fail2ban logs:
```bash
sudo tail -f /var/log/fail2ban.log
```

SSH authentication logs:
```bash
sudo tail -f /var/log/auth.log
```

View recent ban actions:
```bash
sudo grep "Ban" /var/log/fail2ban.log | tail -20
```

## Firewall (UFW) Configuration

### Default Rules
```bash
# Check current rules
sudo ufw status verbose

# Default policy
Default: deny (incoming), allow (outgoing)

# Open ports
22/tcp    - SSH (restricted to admin IPs in GCP firewall)
26656/tcp - CometBFT P2P (open to all validators)
8000/tcp  - API (optional, configurable)
```

### Managing Firewall Rules

Allow a new port:
```bash
sudo ufw allow 8080/tcp comment 'My Service'
```

Remove a rule:
```bash
sudo ufw delete allow 8080/tcp
```

Reload firewall:
```bash
sudo ufw reload
```

## SSH Key Management

### Connecting to Validator

Use the SSH key specified in `admin_ssh_key` variable:

```bash
ssh -i /path/to/private-key ubuntu@<validator-ip>
```

### Adding Additional SSH Keys

1. Connect to the validator
2. Add key to authorized_keys:
```bash
echo "ssh-rsa AAAA... user@host" >> ~/.ssh/authorized_keys
```

3. Verify permissions:
```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### Key Rotation

To rotate SSH keys:

1. Add new key to `authorized_keys`
2. Test connection with new key
3. Remove old key from `authorized_keys`
4. Update Terraform variable for future deployments

## Security Best Practices

### 1. SSH Access
- ✅ Always use SSH keys, never passwords
- ✅ Restrict SSH access to known IP ranges (via GCP firewall)
- ✅ Use unique keys per administrator
- ✅ Rotate keys periodically (every 90-180 days)
- ✅ Disable root login (already configured)

### 2. Firewall Management
- ✅ Only open required ports
- ✅ Use GCP firewall rules for IP restrictions
- ✅ Document all firewall changes
- ✅ Review rules quarterly

### 3. fail2ban Monitoring
- ✅ Review banned IPs weekly
- ✅ Investigate repeated ban attempts
- ✅ Adjust ban duration if needed
- ✅ Set up alerts for high ban rates

### 4. System Updates
```bash
# Update system packages regularly
sudo apt update && sudo apt upgrade -y

# Check for security updates
sudo unattended-upgrades --dry-run
```

### 5. Log Monitoring
- ✅ Review auth.log regularly: `sudo tail -100 /var/log/auth.log`
- ✅ Check fail2ban logs: `sudo tail -100 /var/log/fail2ban.log`
- ✅ Use GCP Cloud Logging for centralized monitoring

## Troubleshooting

### Locked Out of SSH

If you're locked out due to fail2ban:

1. Use GCP Serial Console:
   - Go to Compute Engine > VM instances
   - Click on the instance
   - Click "Connect" > "Connect to serial console"

2. Unban your IP:
```bash
sudo fail2ban-client set sshd unbanip YOUR_IP
```

3. Check why you were banned:
```bash
sudo grep "YOUR_IP" /var/log/auth.log
```

### SSH Key Not Working

1. Verify key is in metadata:
```bash
# On GCP console, check instance metadata for ssh-keys
```

2. Check authorized_keys:
```bash
cat ~/.ssh/authorized_keys
```

3. Check SSH config:
```bash
sudo sshd -t  # Test configuration
sudo journalctl -u sshd -n 50  # View SSH logs
```

4. Temporarily increase SSH logging:
```bash
# Edit /etc/ssh/sshd_config.d/99-hardening.conf
# Change: LogLevel VERBOSE to LogLevel DEBUG3
sudo systemctl restart sshd
```

### fail2ban Not Banning

Check fail2ban status:
```bash
sudo systemctl status fail2ban
```

Test fail2ban:
```bash
# Generate failed login attempts
ssh wronguser@localhost

# Check if IP gets banned
sudo fail2ban-client status sshd
```

Restart fail2ban:
```bash
sudo systemctl restart fail2ban
```

### Emergency SSH Access Recovery

If SSH is completely broken:

1. **Via GCP Console**:
   - Use Serial Console access (requires serial port enabled)
   - Or use "Reset" from Compute Engine console

2. **Restore Original SSH Config**:
```bash
sudo cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
sudo rm /etc/ssh/sshd_config.d/99-hardening.conf
sudo systemctl restart sshd
```

3. **Disable fail2ban Temporarily**:
```bash
sudo systemctl stop fail2ban
```

## Advanced Configuration

### Adjusting fail2ban Thresholds

Edit `/etc/fail2ban/jail.local`:

```bash
sudo nano /etc/fail2ban/jail.local
```

Example - More aggressive banning:
```
[sshd]
maxretry = 2      # Ban after 2 attempts (instead of 3)
findtime = 300    # Look for failures in 5 minutes (instead of 10)
bantime = 7200    # Ban for 2 hours (instead of 1)
```

Restart fail2ban:
```bash
sudo systemctl restart fail2ban
```

### Email Notifications

Configure fail2ban to send email alerts:

1. Install mail utilities:
```bash
sudo apt install mailutils
```

2. Edit `/etc/fail2ban/jail.local`:
```
[DEFAULT]
destemail = admin@example.com
sendername = Fail2Ban-Validator
action = %(action_mwl)s
```

3. Restart fail2ban:
```bash
sudo systemctl restart fail2ban
```

### Whitelisting IPs

To never ban specific IPs, edit `/etc/fail2ban/jail.local`:

```
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 YOUR_ADMIN_IP
```

## Compliance and Auditing

### Security Checklist

- [ ] SSH password authentication disabled
- [ ] Root login disabled
- [ ] fail2ban active and monitoring
- [ ] UFW firewall enabled
- [ ] Only required ports open
- [ ] SSH keys rotated within 180 days
- [ ] System updates applied monthly
- [ ] Logs reviewed weekly
- [ ] Banned IP list reviewed weekly

### Audit Commands

```bash
# Check SSH configuration
sudo sshd -T | grep -i "passwordauthentication\|permitrootlogin"

# Verify fail2ban is running
sudo systemctl is-active fail2ban

# Check firewall status
sudo ufw status numbered

# Review recent authentication attempts
sudo grep "Failed password" /var/log/auth.log | tail -20

# List banned IPs
sudo fail2ban-client status sshd
```

## Docker Deployment Security (zcash-vote-setup)

When using the Docker-based deployment mode (`deployment_mode = "docker"`), the infrastructure relies on the [zcash-vote-setup](https://github.com/hhanh00/zcash-vote-setup) tool. This tool orchestrates the setup using Tailscale and CometBFT containers.

### Step-by-Step Workflow

1. **Server Initialization**:
* The administrator configures `server_config.yml` with a `chainid`, a list of expected `peers` (node names), and a Tailscale `auth` key.
* The server binary (`server.rs`) is started. It creates a local SQLite database (`setup.db`) to track the registration of voting nodes.
* The server imports the initial voting data (`vote.db`) into its setup database to be distributed later.

2. **Node (Client) Registration**:
* Each participant runs the `client` binary, providing the server's URL and their specific node name.
* The client connects to the server and retrieves the shared Tailscale authentication key.
* The client uses **Docker** to start a Tailscale container, which joins the node to a private mesh network.

3. **Consensus Setup**:
* The client initializes a local CometBFT node using Docker.
* It extracts its own unique validator information (Public Key and Node ID) and sends this "Node Definition" back to the server.

4. **Configuration Convergence**:
* The server waits until every node listed in the `peers` configuration has submitted its definition.
* Once all nodes are registered, the server generates a global `genesis.json` (listing all validators) and a `config.toml` (listing all peers).
* The next time a client polls the server, it receives this finalized configuration, the `vote.db` file, and a generated `run.sh` script.

5. **System Launch**:
* The client writes these files to its local disk.
* The `run.sh` script is then used to launch the actual voting server and the CometBFT consensus engine as background processes managed by `supervisord`.

### Security Assumptions and Risks

Running this as a binary release involves several significant security assumptions and potential risks:

#### 1. Trust in the Release and Infrastructure

* **Binary Trust**: Users are instructed to download and run pre-compiled binaries. This assumes the build pipeline (GitHub Actions) and the developer's account are secure and have not been tampered with to include malicious code.
* **Docker Image Trust**: The setup relies on the `hhanh00/zcash-vote-docker` image. Users must trust that this image contains only the claimed software (CometBFT, Tailscale, and the Zcash voting server) without backdoors.

#### 2. Excessive Privileges

* **Privileged Docker Containers**: The setup scripts consistently use the `--privileged` flag when running Docker. This effectively grants the container root-level access to the host machine's kernel and hardware, significantly increasing the risk if the containerized software is compromised.
* **Root/Sudo Requirements**: The installation guide requires the user to be in the `docker` group or use `sudo`. This gives the `client` binary the ability to execute any command on the host via the Docker daemon.

#### 3. Secrets Management

* **Unauthenticated Secret Leakage**: The server's `get_ts_auth_key` gRPC endpoint provides the Tailscale authentication key to **any** requester without requiring a password or token. An attacker who discovers the server's URL can steal this key and join the private Tailscale network.
* **Plaintext Configuration**: Secrets like the Tailscale auth key are stored in plaintext within `server_config.yml` and are passed as environment variables (`TS_AUTHKEY`) to Docker containers.

#### 4. Command Injection Vulnerabilities

* **Shell Execution**: The `run_command_in_container` function in `util.rs` builds shell commands by interpolating variables like `username`, `auth_key`, and `command` into a string before splitting it. While it uses `shell-words` for splitting, complex or malicious inputs could potentially lead to command injection on the host or inside the container.

#### 5. Network Security

* **Insecure RPC**: The setup communication between the client and server occurs over gRPC. Unless configured with external TLS (not explicitly handled in the setup code provided), the node definitions and configuration files are transmitted without encryption, making them vulnerable to interception on the public internet.
  POC or GTFO:
  ```bash
    grpcurl -plaintext \
    -proto protos/server_setup.proto \
    -d '{}' \
    $COORDINATOR_IP:$COORDINATOR_PORT \
    vote_setup.rpc.VoteServerSetup/GetTSAuthKey
  ```

## Support and Resources

- fail2ban documentation: https://www.fail2ban.org/
- Ubuntu SSH hardening: https://help.ubuntu.com/community/SSH/OpenSSH/Configuring
- GCP Security best practices: https://cloud.google.com/security/best-practices

## Reporting Security Issues

If you discover a security vulnerability, please report it to:
- Open an issue on GitHub (for non-critical issues)
- Contact the project maintainers directly (for critical vulnerabilities)
