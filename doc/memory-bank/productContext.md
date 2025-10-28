# Product Context

## Purpose
The zcash-vote-server is a blockchain-based voting application that provides secure, tamper-resistant electronic voting for Zcash community decisions. It uses CometBFT consensus to ensure integrity and prevent manipulation of election results.

## Problems It Solves

### Single Point of Failure
Without blockchain consensus, a single malicious authority could:
- Selectively include or exclude ballots
- Manipulate election results if they have ballot decryption keys
- Compromise election integrity undetected

### Solution: Distributed Consensus
By deploying multiple validators (minimum 4) with 2/3 Byzantine fault tolerance:
- Elections remain secure as long as 2/3 of validators are honest
- No single authority can compromise results
- Transparent, verifiable voting process

## How It Works

### Architecture Overview
1. **Vote Submission**: Users submit ballots via REST API to any node
2. **Consensus Processing**: Votes go through CometBFT ABCI consensus
3. **Validation**: Vote server validates ballots according to election rules
4. **Block Creation**: Valid votes are included in blockchain blocks
5. **Commitment**: Once finalized, votes are committed to database

### Key Components
- **zcash-vote-server**: Rust-based API server and ABCI application
- **CometBFT**: Byzantine fault-tolerant consensus engine
- **SQLite Database**: Persistent storage for elections and ballots
- **REST API**: Interface for vote submission and election queries

### Validator Network
- Minimum 4 validators for production
- Single node acceptable for development/testing
- Validators can manage multiple elections
- Voters can submit to any node in the network

## User Experience Goals

### For Election Administrators
- Easy deployment via infrastructure tooling (Terraform/OpenTofu, Ansible)
- Support for public cloud (GCP), hybrid cloud, or bare metal
- Clear documentation for multi-validator setup
- Ability to manage multiple elections per validator group

### For Voters
- Simple REST API for ballot submission
- Can submit to any validator node
- Transparent verification of vote inclusion

### For Validator Operators
- Clear setup instructions
- Configuration flexibility for different environments
- Monitoring of consensus and block production
- Easy reset procedures for development

## Technical Constraints
- Requires CometBFT v1.0+ installation
- Minimum 4 validators for production security
- Port management for multi-node deployments
- Network connectivity requirements between validators
