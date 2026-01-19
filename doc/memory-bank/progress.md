# Progress

## What Works

### Core Voting Application ✅
- **Blockchain Integration**: Fully functional ABCI integration with CometBFT
- **Vote Submission**: REST API accepts and processes ballots
- **Consensus**: Byzantine fault-tolerant voting with 2/3 agreement threshold
- **Storage**: SQLite database persistence for elections and ballots
- **Cryptography**: Privacy-preserving ballot handling via Orchard protocol

### API Endpoints ✅
- `GET /`: Health check / ballot count
- `GET /election/{id}`: Retrieve election details
- `POST /ballot`: Submit vote
- `GET /num-ballots/{id}`: Get total ballot count for election
- `GET /ballot-height/{id}/{height}`: Get ballot at specific blockchain height

### Election Management ✅
- **Data Directory Scanning**: Automatically loads elections from data directory
- **Commitment Trees**: Maintains CMX frontiers and roots for vote inclusion proofs
- **Multiple Elections**: Single validator group can manage multiple concurrent elections
- **Election Lifecycle**: Track open/closed state in database

### Validator Operations ✅
- **Single Node**: Development and testing mode functional
- **Multi-Validator**: Production deployment with 4+ validators supported
- **State Synchronization**: Deterministic execution ensures consistent state
- **Block Production**: Regular block creation (1 second default interval)

### Configuration ✅
- **Flexible Setup**: Rocket.toml with environment variable overrides
- **Multi-Node Support**: Port configuration for local testing clusters
- **Custom Parameters**: Data path, database path, CometBFT port configurable

### Documentation ✅
- **Deployment Guide**: Comprehensive setup instructions in `doc/deploy.md`
- **Build Instructions**: Clear prerequisites and build commands
- **Reset Procedures**: Development reset workflow documented
- **Multi-Validator Setup**: Production deployment guide available

### Tailscale Integration ✅
- Optional Tailscale-based P2P mesh: implemented and documented (see `infrastructure/docs/TAILSCALE.md`)
- Terraform variables added: `enable_tailscale`, `tailscale_auth_key`, `tailscale_tailnet`, `tailscale_advertise_tags`
- Startup script integration: installs Tailscale when enabled, reads the node's Tailscale IP, binds CometBFT `laddr` to the Tailscale IP, and applies UFW rules restricting P2P access to the Tailscale subnet (100.64.0.0/10)
- Migration and rollback instructions included in the TAILSCALE docs
- Notes:
  - Operators should store auth keys in Secret Manager for production
  - Startup logs tailscale IP when available and continues gracefully with warnings if Tailscale fails

- ✅ **GCP Log-based Metric: Block Height - Complete** (November 6, 2025)
  - **Created `infrastructure/gcp/logging_metric.tf`**: user-defined log metric `cometbft_block_height`
    - Filters syslog `jsonPayload.message` for CometBFT "Committed state" lines
    - Extracts numeric `height` via regex and records values as a distribution
    - Metric configured with DELTA/DISTRIBUTION descriptor and linear buckets
    - Labels: `instance_name` (compute resource name), `zone` (resource.labels.zone)
    - Purpose: enables dashboards/alerts to detect stalled validators and compare heights across nodes
    - Usage note: In Cloud Monitoring, chart `logging.googleapis.com/user/cometbft_block_height` and use the `max` aggregation per `instance_name` to approximate current block height
  - **Deployment**: added as Terraform resource; requires `roles/logging.logWriter` binding for service account (already managed in `main.tf`)
  - **Reference**: `infrastructure/gcp/logging_metric.tf`

## What's Left to Build

### Infrastructure Automation ✅
#### OpenTofu/Terraform - GCP ✅
- [x] GCP infrastructure provisioning scripts (main.tf, variables.tf, outputs.tf)
- [x] Network configuration (VPC, firewall rules)
- [x] Compute instance templates (e2-standard-2, Ubuntu 22.04)
- [x] Static IP allocation
- [x] IAM roles and permissions (service account with minimal privileges)
- [x] Cloud Logging and Monitoring integration
- [x] Automatic snapshot scheduling (daily, 7-day retention)
- [x] Security hardening (SSH restrictions, UFW firewall)
+ 
+ - [x] IAP-only SSH firewall rule (allows 35.235.240.0/20) to support `gcloud --tunnel-through-iap`
+ - [x] `TF_VAR_remote_ssh_enabled` toggle (default false) to opt-in direct SSH and run install-security.sh

### Infrastructure Automation ✅
**GCP Implementation Complete** (October 28, 2025)

#### OpenTofu/Terraform - GCP ✅
- [x] GCP infrastructure provisioning scripts (main.tf, variables.tf, outputs.tf)
- [x] Network configuration (VPC, firewall rules)
- [x] Compute instance templates (e2-standard-2, Ubuntu 22.04)
- [x] Static IP allocation
- [x] IAM roles and permissions (service account with minimal privileges)
- [x] Cloud Logging and Monitoring integration
- [x] Automatic snapshot scheduling (daily, 7-day retention)
- [x] Security hardening (SSH restrictions, UFW firewall)

#### Bootstrap Infrastructure ✅
- [x] bootstrap.sh - Automated project setup script
  - Supports both new project creation and existing project configuration
  - Enables required GCP APIs (Compute, IAM, Logging, Monitoring)
  - Creates Terraform service account with minimal required roles
  - Implements short-lived access token generation (1-hour expiry via impersonation)
  - Optional GCS state bucket creation with versioning
  - Automatic backend.tf generation
  - Comprehensive error handling and validation
- [x] cleanup.sh - Safe bootstrap resource removal
  - Removes Terraform service account and IAM bindings
  - Optional state bucket deletion with confirmation
  - Optional complete project deletion with double confirmation
  - Preserves gcloud.env for future use
- [x] gcloud.env.example - Complete configuration template
  - Bootstrap variables (project, org, billing for new projects)
  - Validator deployment variables (name, SSH, IPs, compute settings)
  - Label format fixed (lowercase only: "zf" not "ZF")
  - Auto-generation section for token commands
  - Usage documentation included

#### Installation Scripts ✅
- [x] Base system setup (install-base.sh)
- [x] Security hardening (install-security.sh)
  - SSH hardening (key-based auth only, no passwords)
  - fail2ban installation and configuration
  - Automatic IP banning for brute force attacks
  - Configuration backup and rollback on failure
- [x] CometBFT installation automation (install-cometbft.sh)
- [x] zcash-vote-server build automation (build-vote-server.sh)
- [x] Systemd service definitions (cometbft.service, zcash-vote-server.service)
- [x] GCP startup script orchestration (startup.sh)
- [x] Integrated security script download
- [x] Configurable CometBFT P2P port
- [x] Cloud-agnostic script design

#### Documentation ✅
- [x] GCP deployment guide (infrastructure/gcp/README.md)
  - Added comprehensive Bootstrap Setup section
  - Bootstrap workflow for existing projects
  - Bootstrap workflow for new projects
  - Security notes about token expiry and re-sourcing
  - Updated State Management section with bootstrap integration
  - Network troubleshooting guidance
- [x] Multi-cloud architecture overview (infrastructure/README.md)
- [x] Environment configuration templates (gcloud.env.example)
- [x] Post-deployment instructions
- [x] Troubleshooting guides
- [x] Cost estimates

#### Deployment Targets
- [x] GCP deployment automation (production-ready)
- [ ] AWS deployment automation (planned)
- [ ] DigitalOcean deployment automation (planned)
- [ ] Hybrid cloud support (architecture ready)
- [ ] Bare metal provisioning scripts (common scripts compatible)

#### Ansible Automation (Future)
- [ ] Playbooks for server configuration
- [ ] Genesis file generation and distribution
- [ ] Validator key management
- [ ] Monitoring setup (Prometheus/Grafana)
- [ ] Log aggregation configuration

### Potential Enhancements 🎯
Not explicitly mentioned but could improve the system:

#### Operational Tools
- [ ] Health check endpoints for monitoring
- [ ] Metrics export (Prometheus format)
- [ ] Backup automation scripts
- [ ] Recovery procedures documentation
- [ ] Upgrade procedure documentation

#### Developer Experience
- [ ] Docker/Docker Compose setup for local testing
- [ ] CI/CD pipeline configuration
- [ ] Automated testing infrastructure
- [ ] Development environment setup scripts

#### Security Hardening
- [ ] TLS certificate automation (Let's Encrypt)
- [ ] Firewall configuration templates
- [ ] Security audit checklist
- [ ] Penetration testing procedures

## Current Status

### Version
**1.0.2** - Stable release

### Maturity Level
- **Core Application**: Production-ready ✅
- **Documentation**: Excellent coverage ✅
- **Infrastructure Tooling - GCP**: Production-ready ✅
- **Infrastructure Tooling - AWS/DO**: Planned 🚧
- **Automation**: Automated GCP deployment ✅

### Known Issues
No critical issues identified. The application is functional and stable.

### Testing Status
- **Manual Testing**: Procedures documented in deployment guide
- **Automated Testing**: Standard Rust unit tests available via `cargo test`
- **Integration Testing**: Multi-validator setup tested manually
- **Load Testing**: Not formally conducted

## Evolution of Project Decisions

### Initial Design
- Started as standalone voting server
- Single-node deployment vulnerable to manipulation

### Security Enhancement
- Added CometBFT consensus integration
- Multi-validator requirement for production
- Achieved Byzantine fault tolerance (2/3 honest validator requirement)
- Addressed security audit findings from Least Authority

### Current Architecture
- Stable ABCI integration
- Flexible deployment options (1 to N validators)
- Clear separation between development and production configurations
- Infrastructure automation planned but deferred

## Deployment History

### Development
- Single-node deployment working
- Local multi-node testing validated
- Reset procedures established

### Production
- Manual multi-validator setup documented
- Deployment guide available
- Actual production deployments: Unknown (likely in progress by users)

## Next Major Milestones

### Short Term
1. **Infrastructure Automation**: Implement Terraform/OpenTofu for GCP
2. **Configuration Management**: Create Ansible playbooks for deployment
3. **Testing**: Set up automated integration tests

### Medium Term
1. **Monitoring**: Add comprehensive observability
2. **Documentation**: Expand operational runbooks
3. **CI/CD**: Automate build and test pipeline

### Long Term
1. **Multi-Cloud**: Extend beyond GCP to AWS, Azure
2. **Performance**: Optimize for larger election scales
3. **Features**: Additional voting mechanisms or election types

## Metrics and KPIs

### Current Capabilities
- **Validator Minimum**: 4 nodes (production)
- **Fault Tolerance**: 33% malicious validators
- **Block Time**: ~1 second
- **Resource Usage**: ~100MB RAM per node
- **Database**: SQLite (sufficient for current scale)

### Scalability Considerations
- Voting workload is relatively low-throughput
- Current architecture suitable for community governance
- SQLite adequate (not enterprise scale)
- Horizontal scaling via additional validators (with consensus overhead)
