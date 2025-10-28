# System Patterns

## Architecture

### High-Level Components

```
┌─────────────────┐
│   Vote Client   │
└────────┬────────┘
         │ REST API
         ▼
┌─────────────────┐      ABCI      ┌──────────────┐
│ zcash-vote-     │◄──────────────►│  CometBFT    │
│    server       │                 │   Engine     │
└────────┬────────┘                 └──────┬───────┘
         │                                  │
         ▼                                  ▼
┌─────────────────┐                 ┌──────────────┐
│  SQLite DB      │                 │  Blockchain  │
│  (vote.db)      │                 │    Data      │
└─────────────────┘                 └──────────────┘
```

### Multi-Validator Network

```
    Voter
      │
      ▼
┌───────────┐     ┌───────────┐     ┌───────────┐     ┌───────────┐
│Validator 1│◄───►│Validator 2│◄───►│Validator 3│◄───►│Validator 4│
│  + Vote   │     │  + Vote   │     │  + Vote   │     │  + Vote   │
│  Server   │     │  Server   │     │  Server   │     │  Server   │
└───────────┘     └───────────┘     └───────────┘     └───────────┘
      │                 │                 │                 │
      └─────────────────┴─────────────────┴─────────────────┘
                    P2P Consensus Network
```

## Key Technical Decisions

### 1. ABCI Integration Pattern
**Decision**: Use Tendermint ABCI to integrate with CometBFT
**Rationale**: 
- Standard blockchain application interface
- Separates consensus logic from application logic
- Allows focus on vote validation and storage

**Implementation**:
- `VoteChain` struct implements ABCI application
- Runs in separate tokio task
- Communicates via TCP on port 26658 (configurable)

### 2. Database Strategy
**Decision**: SQLite for local persistent storage
**Rationale**:
- Simple deployment (single file)
- No separate database server needed
- Adequate performance for voting workload
- Easy backup and reset

**Schema Highlights**:
- `elections` table: Election metadata
- `ballots` table: Cast votes
- `cmx_frontiers` table: Merkle tree frontiers for vote inclusion proofs
- `cmx_roots` table: Merkle tree roots per height

### 3. Async Runtime
**Decision**: Tokio async runtime throughout
**Rationale**:
- Rocket web framework requirement
- ABCI client requires async
- Efficient handling of concurrent requests

### 4. Cryptographic Components
**Decision**: Use Orchard protocol primitives
**Rationale**:
- Privacy-preserving ballot submissions
- Zcash ecosystem integration
- Commitment tree for vote inclusion proofs

**Key Libraries**:
- `zcash-vote`: Core voting protocol
- `orchard`: Cryptographic primitives
- `blake2b_simd`: Fast hashing

## Design Patterns in Use

### Repository Pattern
Database operations abstracted in `db.rs`:
- `create_schema()`: Schema initialization
- `store_election()`: Election persistence
- Ballot storage and retrieval functions

### Dependency Injection
Context pattern for shared state:
```rust
pub struct Context {
    pub pool: SqlitePool,
    pub data_path: String,
    pub comet_bft: u16,
}
```
Managed via Rocket's state system.

### Configuration Management
Layered configuration via Rocket Figment:
- `Rocket.toml`: Default configuration
- Environment variables: Override defaults
- Custom fields under `[default.custom]`

**Key Configuration**:
- `data_path`: Election data directory
- `db_path`: SQLite database location
- `cometbft_port`: ABCI connection port

### Error Handling
Consistent error strategy:
- `anyhow::Result` for internal operations
- Convert to HTTP errors at API boundary
- Structured logging via `tracing`

## Component Relationships

### Chain Module (`chain.rs`)
Implements ABCI application interface:
- `CheckTx`: Validates transactions before mempool
- `FinalizeBlock`: Commits votes to database
- State management for blockchain height

### Routes Module (`routes.rs`)
REST API endpoints:
- `GET /election/{id}`: Election details
- `POST /ballot`: Submit vote
- `GET /num-ballots/{id}`: Vote count
- `GET /ballot-height/{id}/{height}`: Ballot at specific height

### Election Module (`election.rs`)
Election management:
- Scans data directory for election definitions
- Initializes commitment trees
- Manages election lifecycle

### Context Module (`context.rs`)
Application state container:
- Database pool
- Configuration values
- Shared across request handlers

## Critical Implementation Paths

### Vote Submission Flow
1. Client POSTs ballot to `/ballot` endpoint
2. Rocket handler validates format
3. Submit to CometBFT via RPC
4. CometBFT broadcasts to validators
5. Validators run CheckTx validation
6. Block proposer includes in block
7. All validators execute FinalizeBlock
8. Vote committed to local database
9. Response returned to client

### Startup Sequence
1. Initialize tracing subscriber
2. Load Rocket configuration
3. Create Context (DB pool, config)
4. Create database schema
5. Initialize VoteChain ABCI app
6. Start ABCI server (separate thread)
7. Scan and load elections
8. Start Rocket HTTP server

### Multi-Node Consensus
- Each validator maintains own database
- All receive same transactions via gossip
- Deterministic execution ensures consistent state
- 2/3+ agreement required for block finalization
