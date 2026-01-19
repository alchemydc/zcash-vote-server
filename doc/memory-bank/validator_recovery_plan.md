# Validator Recovery & Pre-existing Keys — Plan

Status: design only. Implementation deferred to a future session.

Goal
- Allow spinning up a validator using existing key material and a known set of peers by passing key material and genesis through Terraform variables (multi-cloud) or supporting URL/git sources.
- Validate and auto-start services only when configuration is complete.

Design principles
- Multi-cloud: use terraform.tfvars / -var-file workflow (no cloud-managed secrets required).
- Multi-line JSON: accept base64-encoded JSON strings for key files and genesis to avoid shell/metadata formatting issues.
- Flexible genesis acquisition: accept inline (b64), HTTP(S) URL, or git repo+path+ref.
- Validation: verify JSON structure before writing files.
- Safety: require secrets file to be gitignored and file-permissions restricted.
- Automation: auto-start CometBFT + vote-server only when keys + genesis + peers are present and valid (configurable).

Files to add / change
- New memory-bank doc: `doc/memory-bank/validator_recovery_plan.md` (this file)
- New operator docs: `infrastructure/docs/VALIDATOR_RECOVERY.md`
- Terraform changes: `infrastructure/gcp/variables.tf`, `infrastructure/gcp/main.tf` (metadata), `infrastructure/gcp/outputs.tf`, `infrastructure/gcp/gcloud.env.example`
- Script changes: `infrastructure/gcp/scripts/startup.sh` (flow change), `infrastructure/common/scripts/encode-validator-keys.sh` (helper)
- Tests / checklist: `doc/memory-bank/validator_recovery_tests.md` (optional)

Terraform variable design (multi-cloud)
- Keys (sensitive, base64)
```hcl
variable "priv_validator_key_b64" { type = string, sensitive = true, default = "" }
variable "node_key_b64"           { type = string, sensitive = true, default = "" }
```
- Genesis (priority order: b64 -> url -> git)
```hcl
variable "genesis_json_b64" { type = string, default = "" }
variable "genesis_url"      { type = string, default = "" }
variable "genesis_git_repo" { type = string, default = "" }
variable "genesis_git_path" { type = string, default = "genesis.json" }
variable "genesis_git_ref"  { type = string, default = "main" }
```
- Peers + behaviour
```hcl
variable "persistent_peers"   { type = string, default = "" }
variable "use_existing_keys"  { type = bool,   default = false }
variable "auto_start_services"{ type = bool,  default = true }
```

Operator workflow (recommended)
1. Export variables into a secrets file (gitignored), e.g. `secrets.tfvars`:
   - Use helper script to base64 encode files (local machine).
   - Restrict permissions: `chmod 600 secrets.tfvars`.
2. Apply: `tofu apply -var-file=gcloud.env -var-file=secrets.tfvars`.
3. Startup script will pick up metadata and configure node.

Encoding helper (new script)
- `infrastructure/common/scripts/encode-validator-keys.sh`
- Example:
```bash
# produces base64 compact strings suitable for tfvars
jq -c . priv_validator_key.json | base64 -w0
jq -c . node_key.json | base64 -w0
```
- The script prints `TF_VAR_priv_validator_key_b64 = "..."` style lines.

Startup script changes (overview)
- New decision point before/around `cometbft init`:
  1. If `use_existing_keys` = false: preserve existing flow (cometbft init generates keys).
  2. If true:
     - Create config dir (`/opt/zcash-vote/.cometbft/config`) if missing.
     - If `priv_validator_key_b64` present: base64-decode → write `/opt/zcash-vote/.cometbft/config/priv_validator_key.json`.
       - Validate JSON with `jq` and required fields (address, pub_key, priv_key).
     - If `node_key_b64` present: base64-decode → write `/opt/zcash-vote/.cometbft/config/node_key.json`.
       - Validate JSON with `jq` and required fields (id, priv_key).
     - Run `cometbft init --home /opt/zcash-vote/.cometbft` to generate default config.toml (note: init may overwrite keys).
     - Re-write the key files (restore them) after init so the intended keys persist.
- Genesis acquisition (priority):
  - If `genesis_json_b64` present: decode → write `/opt/zcash-vote/.cometbft/config/genesis.json` → validate (chain_id, validators, genesis_time).
  - Else if `genesis_url` present: `curl -fsS` → save → validate.
  - Else if `genesis_git_repo` present: `git clone` shallow → checkout ref → copy `genesis_git_path`.
  - Else leave missing and log clear POST_DEPLOYMENT instructions.
- Persistent peers:
  - If `persistent_peers` present: sed/replace `persistent_peers = "..."` in config.toml.
- Auto-start:
  - If `auto_start_services` && all required items present & valid → start services:
    - `systemctl start cometbft`
    - wait small grace period, `systemctl start zcash-vote-server`
  - Else leave services disabled and update POST_DEPLOYMENT.md with required manual steps.

Validation details
- Use `jq` for JSON sanity checks (exit non-zero on failures).
- Minimal required assertions:
  - priv_validator_key.json: contains `.address` and `.pub_key` and `.priv_key`.
  - node_key.json: contains `.id` (or `.priv_key`) depending on CometBFT format.
  - genesis.json: contains `.chain_id` and `.validators` and `.genesis_time`.
- On invalid JSON: write a clear log message, do not start services, place diagnostic files in `/var/log/zcash-vote-setup.log`.

Terraform metadata passing
- Add metadata keys to the instance creation resource (strings). Example:
  - `TF_VAR_priv_validator_key_b64` → pass as metadata key `priv-validator-key-b64`.
  - Note size limits on instance metadata; prefer `-var-file` application via Terraform rather than relying on large metadata fields. For large payloads, pass only flags/filenames and rely on `tofu` to create files via startup script reading `gs://` or similar. But per current decision, we will accept `terraform.tfvars` variable values used by userdata/templatefile to render the startup script with embedded base64 values (careful about size).
- Implementation note: embedding large base64 in GCE metadata or cloud-init user-data has size limitations. Use cloud-agnostic approach: Terraform `templatefile()` can write startup script where large variables are included at apply-time (but beware state size & provider limits). If size proves an issue, fallback: upload secrets to an accessible storage (signed URL) in apply-phase.

Security & state considerations
- Storing secrets in tfvars places secrets in:
  - Local file (secrets.tfvars) — recommended for now, must be gitignored and file-permissions protected.
  - Terraform state (if variables used to generate instance metadata or template): state can contain the values — this is acceptable for now but note state exposure risk across backends. Document the risk and recommend migrating to cloud secret manager or a vault for production.
- Add guidance in `gcloud.env.example` and `README` about secret handling and `terraform.tfstate` protections.

Outputs / operator commands
- Provide example outputs and helper text in `infrastructure/gcp/outputs.tf` describing how to create `secrets.tfvars` and how to run `tofu apply -var-file=secrets.tfvars`.
- Provide example `tofu apply` commands and troubleshooting tips.

Testing scenarios (must be validated before production)
1. Fresh bootstrap (existing flow unchanged).
2. Pre-existing keys provided via b64 and genesis inline (full auto-start).
3. Pre-existing keys provided; genesis via URL.
4. Pre-existing keys provided; genesis via git repo/ref/path.
5. Missing genesis or invalid genesis → services left stopped and operators get clear instructions.
6. Invalid keys (malformed JSON) → script fails safe, services not started, logs include diagnostics.
7. Large key files / metadata size test (ensure templatefile or metadata approach doesn't exceed provider limits).

Deliverables for next session (implementation)
- Terraform variable additions and documentation edits.
- Startup script edits and unit-tested shell snippets.
- Helper encoding script and examples in `gcloud.env.example`.
- New `infrastructure/docs/VALIDATOR_RECOVERY.md` with step-by-step operator guides and examples.

Open questions / decisions confirmed by user
- Use terraform.tfvars (multi-cloud) — confirmed.
- Support genesis from URL or git — confirmed.
- Auto-start services when fully configured — confirmed.
- Validate JSON before writing — confirmed.

Next step (this session)
- Document this plan in the memory bank (done).
- Stop; implementation will be scheduled for a future session.
