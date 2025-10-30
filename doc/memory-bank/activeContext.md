# Active Context

## Current Work Focus
**Security Hardening Implementation** (October 29, 2025)

Implemented comprehensive security hardening for validator deployments to protect against SSH brute force attacks. Added fail2ban for automatic IP banning and hardened SSH configuration to allow only key-based authentication.

## Recent Changes
- ✅ **Security Hardening Implementation - Complete** (October 29, 2025)
  - **Created `install-security.sh`**: Standalone security hardening script
    - Disables password authentication (SSH keys only)
    - Hardens SSH configuration (no root login, max 3 attempts, strong ciphers)
    - Installs and configures fail2ban (3 attempts in 10 min = 1 hour ban)
    - Creates backup of SSH config with automatic rollback on failure
    - Validates configuration before applying changes
  - **Updated `install-base.sh`**: Integrated security script into base installation
    - Calls `install-security.sh` as final step (phase 6/6)
    - Gracefully handles missing script for backwards compatibility
  - **Updated `startup.sh`**: Downloads security script from repository
    - Added security script to downloaded files list
    - Ensures security hardening runs on all new deployments
  - **Created comprehensive documentation**: `infrastructure/docs/SECURITY.md`
    - SSH hardening details and configuration locations
    - fail2ban management commands (status, ban/unban IPs)
    - Firewall (UFW) configuration guide
    - SSH key management and rotation procedures
    - Security best practices checklist
    - Troubleshooting guide (locked out, recovery procedures)
    - Advanced configuration (adjusting thresholds, email alerts)
    - Compliance and auditing commands
  - **Key Security Features**:
    - Password authentication: DISABLED
    - Key-based authentication: REQUIRED
    - Root login: DISABLED
    - fail2ban: ACTIVE (automatic IP banning)
    - Configuration backups: AUTOMATIC
    - Rollback on failure: AUTOMATIC

- ✅ **GCP Startup Script Build Fix - Complete** (October 29, 2025)
  - **Issue 1**: Cargo not found - startup script runs in root context without profile sourcing
    - Fixed by explicitly sourcing Rust environment from `$HOME/.cargo/env` or `/root/.cargo/env`
    - Added confirmation message when Rust environment is loaded
  - **Issue 2**: Unbound HOME variable - script uses `set -euo pipefail` which treats unbound vars as errors
    - Fixed by setting `HOME="${HOME:-/root}"` before using it
    - Matches pattern already used in `install-base.sh`
  - **Issue 3**: User permission mismatch - attempted `sudo -u zcash-vote cargo build` but cargo only installed for root
    - Architectural fix: Build as root (who has cargo), then `chown` build artifacts to `zcash-vote` user
    - Removed `export CARGO_HOME` and `sudo -u` from build command
    - Added explicit ownership transfer of `target/` directory after successful build
  - All issues resolved in `infrastructure/common/scripts/build-vote-server.sh`

- ✅ **GCP Bootstrap Infrastructure** (October 28, 2025)
  - Created `bootstrap.sh` - Full project setup automation with new/existing project support
  - Created `cleanup.sh` - Safe removal of bootstrap resources with multiple confirmation levels
  - Created `gcloud.env.example` - Comprehensive configuration template with bootstrap and deployment variables
  - Implemented short-lived access token generation via service account impersonation (1-hour expiry)
  - Fixed Terraform template variable issue in `startup.sh` (`${NODE_ID}` → `$${NODE_ID}`)
  - Updated GCP README with detailed bootstrap documentation and troubleshooting
  - Resolved network configuration issue: project uses `zcash-network` instead of `default`

- ✅ **Infrastructure Implementation** (October 28, 2025 - Prior Work)
  - Created comprehensive OpenTofu/Terraform configuration for GCP
  - Built cloud-agnostic installation scripts (Rust, CometBFT, vote-server)
  - Developed systemd service definitions for production use
  - Implemented automated VM provisioning with security hardening
  - Created extensive documentation and deployment guides
  - Set up multi-cloud directory structure (GCP ready, AWS/DO placeholders)

### Remote SSH and IAP change (October 30, 2025)

- Added a GCP Terraform toggle: `TF_VAR_remote_ssh_enabled` (bool, default = false).
  - Default = false: no public SSH firewall is created; operators must use `gcloud compute ssh --tunnel-through-iap` or a bastion host to access instances.
  - When true: Terraform creates an SSH firewall using `TF_VAR_admin_ip_ranges` and the startup script runs `install-security.sh` (hardens SSH, installs fail2ban).

- Added `google_compute_firewall.ssh_iap` to allow SSH only from Google's IAP proxy CIDR (`35.235.240.0/20`) so IAP TCP forwarding works while SSH remains closed to the public.

- Fixed Terraform `templatefile()` interpolation issues by escaping shell `${...}` sequences as `$${...}` in `infrastructure/gcp/scripts/startup.sh`.

- Rationale: Default-off reduces external attack surface; IAP-only rule preserves secure operator access via `gcloud --tunnel-through-iap`.

## Next Steps
1. Potential follow-up tasks:
   - Test GCP deployment end-to-end
   - Implement AWS infrastructure configuration
   - Implement DigitalOcean infrastructure configuration
   - Create Ansible playbooks for configuration management
   - Add monitoring dashboards (Grafana/Prometheus)
   - Develop CI/CD pipeline for infrastructure testing

## Active Decisions and Considerations

### Project State
- Version: 1.0.2 (stable)
- Primary language: Rust (edition 2021)
- Current deployment: Manual setup documented in `doc/deploy.md`
- **Infrastructure automation: ✅ IMPLEMENTED** - OpenTofu/GCP ready for production use

### Architecture Insights
- **Consensus Model**: Proof of Authority with 2/3 Byzantine fault tolerance
- **Minimum Validators**: 4 for production, 1 acceptable for development
- **Database**: Each validator maintains independent SQLite database
- **Deterministic Execution**: Critical for consensus - all validators must reach same state

### Configuration Patterns
- Rocket.toml for default configuration
- Environment variables for overrides
- Custom fields under `[default.custom]` section
- Multi-node requires careful port management

### Security Considerations
- Single node deployments vulnerable to manipulation
- Multi-validator setup eliminates single points of failure
- Validator key exchange must be secure
- Genesis file coordination required across validators

## Important Patterns and Preferences

### Code Organization
- Modular structure: chain, context, db, election, routes modules
- Clear separation: Web API vs ABCI application logic
- Error handling: anyhow for internal, HTTP errors at boundary
- Async throughout: Tokio runtime, Rocket async handlers

### Infrastructure Organization
- **Multi-cloud architecture**: Separate directories per cloud provider (gcp/, aws/, digitalocean/)
- **Common scripts**: Cloud-agnostic installation scripts in common/scripts/
- **Environment-based configuration**: Variables via environment files (gcloud.env)
- **GitOps-ready**: .gitignore excludes secrets, state files, and sensitive data
- **Modular design**: Reusable components for future cloud provider implementations

### Development Workflow
- High optimization even in debug builds (opt-level = 3)
- Structured logging via tracing
- SQLx compile-time checked queries
- Git dependencies for custom cryptographic components

### Testing Strategy
- Development: Single node with local CometBFT
- Testing: Multi-node on single machine (port conflicts need management)
- Production: Distributed validators with coordinated genesis

## Learnings and Project Insights

### Critical Dependencies
- **CometBFT**: External installation required, not bundled
- **zcash-vote**: Custom fork with specific commit locked
- **orchard**: Patched version for voting primitives
- All dependencies version-pinned for stability

### Deployment Challenges
- Multi-validator setup requires coordination (genesis.json, validator keys)
- Port conflicts in multi-node local testing
- Database and blockchain reset must be synchronized
- Network connectivity requirements between validators

### Performance Characteristics
- Lightweight: ~100MB RAM base usage
- Block production: Every second (configurable in CometBFT)
- SQLite adequate for voting workload
- Low network bandwidth requirements

### Integration Points
1. **ABCI Connection**: TCP port 26658 (vote-server ↔ CometBFT)
2. **REST API**: Port 8000 (clients ↔ vote-server)
3. **P2P Network**: Port 26656 (validator ↔ validator)
4. **RPC**: Port 26657 (CometBFT client interface)

## Current Technical Debt
None identified yet - fresh Memory Bank initialization.

## Operational Notes

### Reset Procedure (Development)
1. Stop both zcash-vote-server and CometBFT
2. Delete vote.db (or configured database)
3. Run `cometbft unsafe-reset-all`
4. Restart both services

### Adding New Validator
1. Initialize CometBFT on new node
2. Extract validator public key from priv_validator_key.json
3. Update genesis.json with new validator
4. Distribute updated genesis.json to all nodes
5. Configure persistent_peers with other validators
6. Start services

### Monitoring Points
- Block height progression
- Vote submission success rate
- Consensus participation (validator signatures)
- Database growth
- API response times

## Context for AI Assistant

### Memory Bank Philosophy
After each session reset, I (Cline) rely entirely on these Memory Bank files to understand the project. This activeContext.md file tracks current state and recent work, making it crucial for continuity.

### When to Update
- After implementing significant changes
- When discovering new patterns or insights
- When user requests with **update memory bank**
- When context needs clarification

### Project Maturity
- Core application: Mature and functional (v1.0.2)
- Infrastructure tooling: Mentioned in Project Brief but not yet implemented
- Documentation: Good coverage in deployment guide
- Testing: Manual testing procedures documented
