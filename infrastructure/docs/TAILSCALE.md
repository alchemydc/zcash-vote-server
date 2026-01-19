# Tailscale Integration Guide

This document describes how to enable and operate Tailscale for encrypted CometBFT P2P networking in the zcash-vote-server infrastructure.

## Overview

When `TF_VAR_enable_tailscale=true` the deployment will:
- Avoid creating a public GCP firewall rule for the CometBFT P2P port.
- Install and join Tailscale on each validator during startup.
- Configure CometBFT to bind to the node's Tailscale IP.
- Restrict the node's local UFW to accept P2P connections only from the Tailscale subnet (100.64.0.0/10).

This approach encrypts P2P traffic over a Tailscale WireGuard mesh and prevents the P2P port from being exposed to the public internet.

---

## Single-Coordinator / Multi-Participant POC (Approach A)

This section explains a minimal, operational POC pattern where one coordinator (the tailnet administrator) operates a single shared Tailnet and distributes auth keys to participating organizations.

### Roles
- Coordinator (Tailnet admin)
  - Owns the tailnet and Tailscale admin console.
  - Generates and distributes reusable/auth-scoped keys for POC participants.
  - Publishes ACL tag policy for validators (e.g., `tag:validator`).
- Participant (Validator operator)
  - Receives an auth key and tailnet name from the coordinator.
  - Deploys a validator using the provided auth key.
  - Shares Node ID, validator public key, and assigned Tailscale IP with other participants for genesis/peering.

### Coordinator steps (one-time)
1. Create or use an existing Tailscale account and tailnet.
2. Define tag ownership & ACLs in the Tailscale admin console. Minimal ACL example:
```json
{
  "tagOwners": {
    "tag:validator": ["group:admins"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["tag:validator"],
      "dst": ["tag:validator:26656"]
    }
  ]
}
```
3. Generate scoped/reusable auth keys for participants:
   - Prefer keys with TTL and `tag:validator`.
   - Use Tailscale admin UI or CLI per https://tailscale.com/kb/1595/secure-auth-key-cli.
4. Distribute each participant's auth key and the tailnet name securely (out-of-band).

### Participant steps (per-validator)
1. Prepare `gcloud.env` or export variables:
```bash
export TF_VAR_enable_tailscale=true
export TF_VAR_tailscale_auth_key="tskey-auth-..."
export TF_VAR_tailscale_tailnet="coordinator-tailnet.tailscale.net"
export TF_VAR_tailscale_advertise_tags='["tag:validator"]'
```
2. Deploy:
```bash
source infrastructure/gcp/gcloud.env
tofu plan
tofu apply
```
3. Verify Tailscale status and obtain the node's Tailscale IP:
```bash
# via Terraform output
tofu output -raw tailscale_ip_command

# then run the returned command (example)
gcloud compute ssh validator-01 --zone us-central1-a --tunnel-through-iap 'tailscale ip -4'
```
4. Retrieve Node ID and validator public key:
```bash
gcloud compute ssh validator-01 --zone us-central1-a --tunnel-through-iap --command="sudo -u zcash-vote cometbft show-node-id --home /opt/zcash-vote/.cometbft"
gcloud compute ssh validator-01 --zone us-central1-a --tunnel-through-iap --command="sudo -u zcash-vote cometbft show-address --home /opt/zcash-vote/.cometbft"
```
5. Share Tailscale IP + Node ID + Validator public key with the genesis coordinator / peer coordinators (out-of-band).
6. After genesis.json and persistent_peers are coordinated, update `config.toml` persistent_peers using `node_id@TAILSCALE_IP:PORT` and start services:
```bash
sudo systemctl start cometbft
sudo systemctl start zcash-vote-server
```

### POC Coordination Checklist (concise)
- [ ] Coordinator created tailnet and ACLs.
- [ ] Coordinator generated auth keys for each participant.
- [ ] Each participant received auth key and tailnet name.
- [ ] Each participant deployed instance with `TF_VAR_enable_tailscale=true`.
- [ ] Participants collected Tailscale IPs and Node IDs.
- [ ] Genesis completed and distributed.
- [ ] Persistent peers configured using Tailscale IPs.
- [ ] Services started and validators entered consensus.

### Troubleshooting POC-specific issues
- If a participant's node shows no Tailscale IP:
  - Confirm auth key is valid and not expired.
  - Confirm outbound HTTPS is allowed from the instance (tailscaled needs reachability).
  - Inspect `journalctl -u tailscaled` and `tailscale status`.
- If validators cannot connect:
  - Confirm ACL tags are applied to devices in the admin console.
  - Confirm `ufw` on the instance allows the Tailscale subnet (100.64.0.0/10).
  - Confirm `laddr` binding in `/opt/zcash-vote/.cometbft/config/config.toml` uses the Tailscale IP.

---

## Generate a Headless Auth Key (recommended)

Create a scoped/reusable auth key in the Tailscale admin console per:
https://tailscale.com/kb/1595/secure-auth-key-cli

Example (admin console UI or CLI):
- Create a key with appropriate tags (e.g., `tag:validator`) and an expiration.
- Copy the key value (e.g., `tskey-auth-...`).

---

## Secure Storage of the Auth Key

Do NOT commit auth keys to source control or store them in plaintext. Recommended options:

1. Google Secret Manager (recommended for production)
   - Create secret:
```bash
echo -n "tskey-auth-..." | gcloud secrets create tailscale-auth-key --data-file=-
```
   - Grant the validator service account access (Terraform can manage this).
   - Reference the secret in your deployment workflow and set `TF_VAR_tailscale_auth_key` securely at apply time.

2. Local secrets.tfvars (development only)
```hcl
# secrets.tfvars
tailscale_auth_key = "tskey-auth-..."
```
Run:
```bash
tofu apply -var-file=secrets.tfvars
```

---

## Terraform variables

Files modified / added:
- `infrastructure/gcp/variables.tf` — new variables: `enable_tailscale`, `tailscale_auth_key`, `tailscale_tailnet`, `tailscale_advertise_tags`
- `infrastructure/gcp/main.tf` — conditional firewall (P2P not created when Tailscale enabled) and optional Secret Manager IAM binding
- `infrastructure/gcp/outputs.tf` — outputs reporting Tailscale enablement and commands to fetch Tailscale IP

Set in `gcloud.env` (example):
```bash
export TF_VAR_enable_tailscale=true
export TF_VAR_tailscale_auth_key="tskey-auth-..."
export TF_VAR_tailscale_tailnet="myorg.tailscale.net"
export TF_VAR_tailscale_advertise_tags='["tag:validator"]'
```

Prefer passing auth key via Secret Manager or a secure pipeline instead of exporting in a shell for production.

---

## Node bootstrap behavior

The startup script will:
1. Run `install-base.sh`.
2. If `enable_tailscale` is set, call `install-tailscale.sh` with the auth key.
3. Read the assigned Tailscale IP (`tailscale ip -4`).
4. Initialize CometBFT and update `laddr` in `config.toml` to bind to the Tailscale IP and configured P2P port.
5. Apply a UFW rule that allows the configured P2P port only from `100.64.0.0/10`.

If Tailscale fails to come up, the startup script logs a warning and continues; operators must verify connectivity before starting services.

---

## ACL / Tag example

Example ACL snippet (Tailscale admin) to allow validator-to-validator P2P traffic:
```json
{
  "tagOwners": {
    "tag:validator": ["group:admins"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["tag:validator"],
      "dst": ["tag:validator:26656"]
    }
  ]
}
```
Adjust port to match `TF_VAR_cometbft_p2p_port` if non-default.

---

## Post-deploy checklist

- Verify Tailscale status on each node:
```bash
tailscale status
tailscale ip -4
```
- Collect Tailscale IPs for each validator and use them for `persistent_peers`:
  - Format: `node_id@TAILSCALE_IP:${TF_VAR_cometbft_p2p_port}`
- Confirm the public CometBFT firewall rule is not present when Tailscale is enabled:
```bash
gcloud compute firewall-rules list --filter="name~${TF_VAR_validator_name}.*cometbft"
```

---

## Troubleshooting

- tailscale up failed:
  - Verify the auth key is valid, not expired, and has correct tags.
  - Check `journalctl -u tailscaled` and `tailscale status`.
- No Tailscale IP assigned:
  - Confirm the machine can reach Tailscale control (outbound HTTPS allowed).
  - Ensure auth key and tailnet are correct.
- Peers can't connect:
  - Validate ACLs and advertised tags in the Tailscale admin console.
  - Confirm CometBFT is bound to the Tailscale IP and port, and that UFW is allowing the Tailscale subnet.

---

## Migration and rollback

- To migrate existing validators to Tailscale:
  1. Enable Tailscale for one validator, verify connectivity, update peers to use Tailscale IPs.
  2. Disable/ remove public firewall rule after verifying connectivity.
  3. Repeat for remaining validators.

- To rollback:
  - Set `TF_VAR_enable_tailscale=false` and run `tofu apply` to re-create the public P2P firewall rule and revert binding behavior. Reconfigure `persistent_peers` to use public IPs.

---

## Security notes

- Use scoped, reusable auth keys with an appropriate TTL.
- Prefer Secret Manager and the least-privilege model.
- Do not enable exit nodes or advertise internet routes from validator machines.
- Monitor Tailscale device list and revoke lost/stolen devices promptly.
