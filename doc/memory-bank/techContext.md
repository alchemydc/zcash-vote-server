# Tech Context

## Technology Stack

### Core Language
- **Rust** (Edition 2021)
  - Memory safety without garbage collection
  - Strong type system for reliability
  - Excellent async/await support
  - Native performance for cryptographic operations

### Web Framework
- **Rocket 0.5.1**
  - Modern async web framework
  - Type-safe routing and request handling
  - Built-in JSON support
  - Configuration via Figment
  - TLS support for secure communications

### Blockchain Integration
- **CometBFT** (formerly Tendermint BFT)
  - Byzantine fault-tolerant consensus
  - ABCI (Application Blockchain Interface)
  - Version: Compatible with 0.40.1 client library
  - Must be installed separately (not bundled)

### Database
- **SQLite** via sqlx 0.8
  - Embedded database (no separate server)
  - Async query support via sqlx
  - Compile-time checked queries with macros
  - Bundled libsqlite3-sys (no system dependency)

### Cryptography
- **zcash-vote** (custom git dependency)
  - Core voting protocol implementation
  - Privacy-preserving ballot handling
  - Git rev: f05f5f2569f286f3ef09ed7edfd008a6b4f35777

- **orchard 0.11.0** (patched)
  - Zcash Orchard protocol primitives
  - Commitment trees for vote inclusion proofs
  - Custom fork: github.com/hhanh00/orchard
  - Rev: 75448e671f56f7c6d3f29502f5a26370a056b86c

- **blake2b_simd 1.0.2**
  - Fast cryptographic hashing
  - SIMD-optimized implementation

### Async Runtime
- **Tokio**
  - Async runtime for all I/O operations
  - Required by Rocket and ABCI client
  - Multi-threaded executor

### Key Dependencies
```toml
anyhow = "1.0.95"              # Error handling
tracing = "0.1.40"             # Structured logging
serde = "1" + serde_json       # Serialization
bincode = "1.3.3"              # Binary serialization
sqlx = "0.8"                   # Database driver
rocket = "0.5.1"               # Web framework
rocket_cors = "0.6.0"          # CORS support
tendermint-abci = "0.40.1"     # ABCI client
tendermint = "0.40.1"          # Core types
base64 = "0.22"                # Encoding
reqwest = "0.12"               # HTTP client
```

## Development Setup

### Prerequisites
**Ubuntu/Debian**:
```bash
sudo apt install build-essential libssl-dev pkg-config
```

**macOS**: Xcode Command Line Tools
**Windows**: MSVC toolchain via rustup

### Rust Toolchain
- Install via rustup: https://rustup.rs/
- Minimum version: Rust 2021 edition support
- Cargo for build management

### CometBFT Installation
- Download from official releases: https://github.com/cometbft/cometbft/releases
- Extract binary to PATH
- Version: 1.0+ recommended

### Build Commands
```bash
# Development build
cargo build

# Release build (optimized)
cargo build --release
# or
cargo b -r

# Run tests
cargo test

# Run with custom config
ROCKET_CONFIG=node1.toml cargo run
```

### Development Profile
Optimized for debugging:
```toml
[profile.dev]
opt-level = 3    # High optimization even in debug
debug = true     # Keep debug symbols
```

## Configuration

### Rocket.toml Structure
```toml
[default]
port = 8000
address = "0.0.0.0"

[default.custom]
data_path = "data"           # Election data directory
db_path = "vote.db"          # SQLite database file
cometbft_port = 26658        # ABCI connection port
```

### Environment Variables
Override any Rocket config:
```bash
ROCKET_PORT=8080
ROCKET_CUSTOM_DB_PATH=/path/to/db
ROCKET_CONFIG=custom.toml
```

### Multi-Node Configuration
For local testing with multiple nodes:
- Separate CometBFT home directories
- Unique port sets per node (ABCI, RPC, P2P)
- Different database paths
- Set `allow_duplicate_ip = true` in config.toml

**Example Ports**:
- Node 1: 26658, 26657, 26656
- Node 2: 26668, 26667, 26666
- Node 3: 26678, 26677, 26676
- Node 4: 26688, 26687, 26686

## Technical Constraints

### Platform Support
- Linux: Fully supported (primary target)
- macOS: Supported for development
- Windows: Build possible but less tested

### Network Requirements
- TCP connectivity between validators
- Ports must be accessible:
  - ABCI: Default 26658
  - RPC: Default 26657
  - P2P: Default 26656
  - HTTP API: Default 8000

### Resource Requirements
- Minimal CPU (single-threaded operation sufficient)
- RAM: ~100MB base + data size
- Disk: SQLite database grows with votes
- Network: Low bandwidth (vote submissions only)

### Deployment Constraints
- CometBFT must be installed separately
- Each validator needs unique IP or port configuration
- Genesis file must be coordinated across validators
- Validator keys must be exchanged securely

## Tool Usage Patterns

### Building
```bash
# Standard build
cargo build --release

# Check without building
cargo check

# Build with specific features
cargo build --features "tls"
```

### Running
```bash
# Development
cargo run

# Production (after build)
./target/release/zcash-vote-server

# With custom config
ROCKET_CONFIG=production.toml ./target/release/zcash-vote-server
```

### CometBFT Operations
```bash
# Initialize new chain
cometbft init

# Start node
cometbft node

# With custom home directory
cometbft --home ~/.cometbft/node1 init
cometbft --home ~/.cometbft/node1 node

# Show node ID (for peer configuration)
cometbft show-node-id

# Reset blockchain (DANGEROUS)
cometbft unsafe-reset-all
```

### Database Management
```bash
# Connect to database
sqlite3 vote.db

# Backup
cp vote.db vote.db.backup

# Reset (stop server first!)
rm vote.db
cometbft unsafe-reset-all
```

## Dependencies Management

### Git Dependencies
Custom forks used for specific features:
- `zcash-vote`: Core protocol (locked to specific commit)
- `orchard`: Modified Orchard implementation

### Patching Strategy
Cargo patches allow replacing crates:
```toml
[patch.crates-io]
orchard = { git = "...", rev = "..." }

[patch."https://github.com/..."]
# Optional local development overrides
```

### Version Pinning
- Most dependencies pinned to specific versions
- Critical security: Update regularly
- Test thoroughly after updates (consensus compatibility)
