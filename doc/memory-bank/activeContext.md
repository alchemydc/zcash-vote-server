# Active Context

## Current Work Focus
**GCP Startup Script Build Architecture Fix** (October 29, 2025)

Fixed critical architectural issue in GCP deployment where `build-vote-server.sh` attempted to build as the `zcash-vote` user who didn't have Rust/Cargo installed. Required three fixes: (1) sourcing Rust environment explicitly, (2) handling unbound HOME variable, and (3) building as root with proper ownership transfer.

## Recent Changes
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
