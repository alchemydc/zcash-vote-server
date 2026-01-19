# Proposed Fix: Complete Elimination of Non-Deterministic `id_election` Usage

**Status:** Proposal for Review  
**Date:** November 12, 2025  
**Priority:** Critical - Consensus Failure  
**Reviewers:** @hhahn00

---

## Executive Summary

My previous fix (PR #61) was **incomplete**. It only addressed the AppHash calculation but left the non-deterministic `id_election` integer flowing through the entire application logic, causing:

- **CheckTx failures** that differ between validators
- **Database state corruption** with incorrect election associations
- **Consensus failures** due to different validators processing blocks differently
- **Unrecoverable blockchain state** requiring full cluster reset

This proposal provides a **complete refactoring** to eliminate all non-deterministic behavior by using only the deterministic TEXT `id` field in application logic, while keeping `id_election` as an internal database optimization.

---

## Root Cause Analysis

### The Non-Determinism Chain

1. **Filesystem Order** → `scan_data_dir()` uses `std::fs::read_dir()` which returns files in **arbitrary, non-deterministic order**
2. **Database Insertion** → Elections inserted in filesystem order, receiving auto-increment `id_election` values
3. **Toxic Propagation** → Functions receive deterministic `id` (TEXT) but immediately convert to non-deterministic `id_election` (INTEGER)
4. **State Divergence** → Different validators query/write different data based on their unique `id_election` mappings

### Example Scenario

**Validator 1 filesystem returns:** `[election-A.json, election-B.json]`
- election-A gets `id_election = 1`
- election-B gets `id_election = 2`

**Validator 2 filesystem returns:** `[election-B.json, election-A.json]`
- election-B gets `id_election = 1`
- election-A gets `id_election = 2`

**Result:** When processing a ballot for "election-A":
- Validator 1 queries `cmx_roots WHERE election = 1` → finds election-A data ✓
- Validator 2 queries `cmx_roots WHERE election = 2` → finds election-A data ✓
- **BUT** if validator 2's data was written using `id_election = 1`, it queries the wrong data → CheckTx failure

---

## Current Database Schema

```sql
CREATE TABLE elections(
    id_election INTEGER PRIMARY KEY,  -- Auto-increment (NON-deterministic)
    id TEXT NOT NULL UNIQUE,          -- From JSON file (DETERMINISTIC)
    definition TEXT NOT NULL,
    closed BOOLEAN NOT NULL
);

-- Foreign key relationships in zcash-vote crate tables:
-- ballots.election → elections.id_election
-- cmx_roots.election → elections.id_election
-- cmx_frontiers.election → elections.id_election
-- dnfs.election → varies (likely TEXT or INTEGER)
```

**Key Insight:** The `id` column has a `UNIQUE` constraint, making it suitable for JOINs. We don't need to change the schema.

---

## Proposed Solution: Hide `id_election` from Application Logic

### Strategy

1. **Keep** `id_election` as an internal database optimization (INTEGER joins are fast)
2. **Remove** `id_election` from all Rust function signatures
3. **Resolve** `id` → `id_election` mapping **within SQL queries** using JOINs/subqueries
4. **Never** pass `id_election` between functions - only pass `id` (TEXT)

This isolates the non-determinism to the database layer where it becomes harmless.

---

## Implementation Plan

### Phase 1: Refactor `src/db.rs` Functions

#### 1.1 `get_election` - Remove `id_election` from Return Value

**Current (Incorrect):**
```rust
pub async fn get_election(
    connection: &mut SqliteConnection,
    id: &str,
) -> Result<(u32, String, bool)> {
    let res: (u32, String, bool) =
        sqlx::query_as("SELECT id_election, definition, closed FROM elections WHERE id = ?1")
            .bind(id)
            .fetch_one(&mut *connection)
            .await?;
    Ok(res)
}
```

**Proposed (Correct):**
```rust
pub async fn get_election(
    connection: &mut SqliteConnection,
    id: &str,
) -> Result<(String, bool)> {
    let res: (String, bool) =
        sqlx::query_as("SELECT definition, closed FROM elections WHERE id = ?1")
            .bind(id)
            .fetch_one(&mut *connection)
            .await?;
    Ok(res)
}
```

**Rationale:** Stop leaking the non-deterministic `id_election` to callers.

---

#### 1.2 `check_cmx_root` - Use TEXT `id` with JOIN

**Current (Incorrect):**
```rust
pub async fn check_cmx_root(
    connection: &mut SqliteConnection,
    id_election: u32,
    cmx: &[u8],
) -> Result<()> {
    let r = sqlx::query("SELECT 1 FROM cmx_roots WHERE election = ?1 AND hash = ?2")
        .bind(id_election)
        .bind(cmx)
        .fetch_optional(&mut *connection)
        .await?;
    r.ok_or(anyhow::anyhow!("Invalid cmx root"))?;
    Ok(())
}
```

**Proposed (Correct):**
```rust
pub async fn check_cmx_root(
    connection: &mut SqliteConnection,
    election_id: &str,
    cmx: &[u8],
) -> Result<()> {
    let r = sqlx::query(
        "SELECT 1 FROM cmx_roots r
         JOIN elections e ON r.election = e.id_election
         WHERE e.id = ?1 AND r.hash = ?2"
    )
    .bind(election_id)
    .bind(cmx)
    .fetch_optional(&mut *connection)
    .await?;
    r.ok_or(anyhow::anyhow!("Invalid cmx root"))?;
    Ok(())
}
```

**Rationale:** Resolve `id` → `id_election` via JOIN at query time.

---

#### 1.3 `store_ballot` - Use TEXT `id` with Subquery

**Current (Incorrect):**
```rust
pub async fn store_ballot(
    connection: &mut SqliteConnection,
    id_election: u32,
    height: u32,
    ballot: &Ballot,
    cmx_root: &[u8],
) -> Result<u32>
```

**Proposed (Correct):**
```rust
pub async fn store_ballot(
    connection: &mut SqliteConnection,
    election_id: &str,
    height: u32,
    ballot: &Ballot,
    cmx_root: &[u8],
) -> Result<u32> {
    let hash = ballot.data.sighash()?;
    
    // Use subquery to resolve id → id_election for INSERT
    let r = sqlx::query(
        "INSERT INTO ballots (election, height, hash, data)
         VALUES ((SELECT id_election FROM elections WHERE id = ?1), ?2, ?3, ?4)"
    )
    .bind(election_id)
    .bind(height)
    .bind(&hash)
    .bind(serde_json::to_string(ballot)?)
    .execute(&mut *connection)
    .await?;
    let id_ballot = r.last_insert_rowid() as u32;

    // For store_cmx_root (zcash-vote crate), we must fetch id_election
    let (id_election,): (u32,) = sqlx::query_as(
        "SELECT id_election FROM elections WHERE id = ?1"
    )
    .bind(election_id)
    .fetch_one(&mut *connection)
    .await?;
    
    store_cmx_root(connection, id_election, id_ballot, cmx_root).await?;
    Ok(id_ballot)
}
```

**Rationale:** Accept deterministic `election_id`, resolve to `id_election` only when calling external `zcash-vote` crate functions.

---

#### 1.4 `get_ballot_height` - Use TEXT `id` with JOIN

**Current (Incorrect):**
```rust
pub async fn get_ballot_height(
    connection: &mut SqliteConnection,
    id_election: u32,
    height: u32,
) -> Result<String>
```

**Proposed (Correct):**
```rust
pub async fn get_ballot_height(
    connection: &mut SqliteConnection,
    election_id: &str,
    height: u32,
) -> Result<String> {
    let (data,): (String,) = sqlx::query_as(
        "SELECT b.data FROM ballots b
         JOIN elections e ON b.election = e.id_election
         WHERE e.id = ?1 AND b.height = ?2"
    )
    .bind(election_id)
    .bind(height)
    .fetch_one(&mut *connection)
    .await?;
    Ok(data)
}
```

---

#### 1.5 `get_num_ballots` - Use TEXT `id` with JOIN

**Current (Incorrect):**
```rust
pub async fn get_num_ballots(
    connection: &mut SqliteConnection,
    id_election: u32
) -> Result<u32>
```

**Proposed (Correct):**
```rust
pub async fn get_num_ballots(
    connection: &mut SqliteConnection,
    election_id: &str
) -> Result<u32> {
    let (count,): (u32,) = sqlx::query_as(
        "SELECT COUNT(*) FROM ballots b
         JOIN elections e ON b.election = e.id_election
         WHERE e.id = ?1"
    )
    .bind(election_id)
    .fetch_one(&mut *connection)
    .await?;
    Ok(count)
}
```

---

### Phase 2: Refactor `src/chain.rs`

#### 2.1 `Command::CheckBallot` (Lines 228-271)

**Changes Required:**

```rust
// Line 233: Update get_election call
// BEFORE:
let (id_election, election, closed) = 
    get_election(&mut self.connection, id).await.map_err(anyhow::Error::msg)?;

// AFTER:
let (election, closed) = 
    get_election(&mut self.connection, id).await.map_err(anyhow::Error::msg)?;

// Line 249: Update check_cmx_root call
// BEFORE:
check_cmx_root(&mut self.connection, id_election, &data.anchors.cmx)
    .await.map_err(anyhow::Error::msg)?;

// AFTER:
check_cmx_root(&mut self.connection, id, &data.anchors.cmx)
    .await.map_err(anyhow::Error::msg)?;
```

---

#### 2.2 `Command::FinalizeBallot` (Lines 305-399)

**Multiple changes required:**

```rust
// Line 307: Update get_election call
// BEFORE:
let (id_election, _, closed) = get_election(&mut self.connection, id).await?;

// AFTER:
let (_, closed) = get_election(&mut self.connection, id).await?;

// Lines 315-316: Update cmx_frontiers MAX(height) query
// BEFORE:
let (height,): (u32,) =
    sqlx::query_as("SELECT MAX(height) FROM cmx_frontiers WHERE election = ?1")
        .bind(id_election)
        .fetch_one(&mut self.connection)
        .await?;

// AFTER:
let (height,): (u32,) = sqlx::query_as(
    "SELECT MAX(f.height) FROM cmx_frontiers f
     JOIN elections e ON f.election = e.id_election
     WHERE e.id = ?1"
)
.bind(id)
.fetch_one(&mut self.connection)
.await?;

// Lines 321-324: Update cmx_frontiers SELECT query
// BEFORE:
let mut cmx_frontier = sqlx::query(
    "SELECT frontier FROM cmx_frontiers WHERE election = ?1 AND height = ?2")
    .bind(id_election).bind(height)
    .map(|r: SqliteRow| {
        let cmx_frontier: String = r.get(0);
        serde_json::from_str::<Frontier>(&cmx_frontier)
    }).fetch_one(&mut self.connection).await??;

// AFTER:
let mut cmx_frontier = sqlx::query(
    "SELECT f.frontier FROM cmx_frontiers f
     JOIN elections e ON f.election = e.id_election
     WHERE e.id = ?1 AND f.height = ?2")
    .bind(id).bind(height)
    .map(|r: SqliteRow| {
        let cmx_frontier: String = r.get(0);
        serde_json::from_str::<Frontier>(&cmx_frontier)
    }).fetch_one(&mut self.connection).await??;

// Line 329: Update store_dnf call (requires wrapper function)
// BEFORE:
store_dnf(&mut self.connection, id_election, &action.nf)
    .await
    .map_err(|_| {
        anyhow::anyhow!("Duplicate nullifier: double spend")
    })?;

// AFTER:
store_dnf_by_id(&mut self.connection, id, &action.nf)
    .await
    .map_err(|_| {
        anyhow::anyhow!("Duplicate nullifier: double spend")
    })?;

// Lines 339-344: Update cmx_frontiers INSERT query
// BEFORE:
sqlx::query(
    "INSERT INTO cmx_frontiers(election, height, frontier)
    VALUES (?1, ?2, ?3)",
)
.bind(id_election)
.bind(height + 1)
.bind(&cmx_frontier)
.execute(&mut self.connection)
.await?;

// AFTER:
sqlx::query(
    "INSERT INTO cmx_frontiers(election, height, frontier)
    VALUES ((SELECT id_election FROM elections WHERE id = ?1), ?2, ?3)",
)
.bind(id)
.bind(height + 1)
.bind(&cmx_frontier)
.execute(&mut self.connection)
.await?;

// Line 350: Update get_num_ballots call
// BEFORE:
let height = crate::db::get_num_ballots(&mut self.connection, id_election).await?;

// AFTER:
let height = crate::db::get_num_ballots(&mut self.connection, id).await?;

// Line 352: Update store_ballot call
// BEFORE:
store_ballot(&mut self.connection, id_election, height + 1, ballot, &cmx_root).await?;

// AFTER:
store_ballot(&mut self.connection, id, height + 1, ballot, &cmx_root).await?;
```

---

### Phase 3: Handle `zcash-vote` Crate Dependencies

The external `zcash-vote` crate provides `store_dnf` and `store_cmx_root` which currently expect `id_election: u32`. We have two implementation options:

---

#### **Option A: Wrapper Functions in zcash-vote-server** (SHORT-TERM)

Add wrapper functions to `src/db.rs` in **zcash-vote-server**:

```rust
/// Wrapper to convert election TEXT id to id_election for zcash-vote crate
pub async fn store_dnf_by_id(
    connection: &mut SqliteConnection,
    election_id: &str,
    nf: &[u8],
) -> Result<()> {
    // Resolve id → id_election
    let (id_election,): (u32,) = sqlx::query_as(
        "SELECT id_election FROM elections WHERE id = ?1"
    )
    .bind(election_id)
    .fetch_one(&mut *connection)
    .await?;
    
    // Call zcash-vote crate function
    zcash_vote::db::store_dnf(connection, id_election, nf).await
}
```

**Pros:**
- ✅ No changes to zcash-vote crate required
- ✅ Can deploy immediately
- ✅ Isolates the fix to one repository

**Cons:**
- ❌ Extra database query on every call (performance overhead)
- ❌ Doesn't solve the root problem in zcash-vote
- ❌ Other consumers of zcash-vote will have the same issue

---

#### **Option B: Refactor zcash-vote Crate** (LONG-TERM, RECOMMENDED)

Modify the `zcash-vote` crate to accept TEXT `election_id` instead of `u32 id_election`.

##### **Affected Functions in zcash-vote Crate**

Based on usage in zcash-vote-server, the following functions need refactoring:

1. **`zcash_vote::db::store_dnf`**
   - Current signature: `pub async fn store_dnf(connection: &mut SqliteConnection, id_election: u32, nf: &[u8]) -> Result<()>`
   - Proposed signature: `pub async fn store_dnf(connection: &mut SqliteConnection, election_id: &str, nf: &[u8]) -> Result<()>`

2. **`zcash_vote::db::store_cmx_root`**
   - Current signature: `pub async fn store_cmx_root(connection: &mut SqliteConnection, id_election: u32, id_ballot: u32, cmx_root: &[u8]) -> Result<()>`
   - Proposed signature: `pub async fn store_cmx_root(connection: &mut SqliteConnection, election_id: &str, id_ballot: u32, cmx_root: &[u8]) -> Result<()>`

##### **Required Changes to zcash-vote Crate**

**File: `zcash-vote/src/db.rs` (or equivalent)**

**1. Refactor `store_dnf`:**

```rust
// BEFORE
pub async fn store_dnf(
    connection: &mut SqliteConnection,
    id_election: u32,
    nf: &[u8],
) -> Result<()> {
    sqlx::query(
        "INSERT INTO dnfs(election, hash) VALUES (?1, ?2)"
    )
    .bind(id_election)
    .bind(nf)
    .execute(&mut *connection)
    .await?;
    Ok(())
}

// AFTER
pub async fn store_dnf(
    connection: &mut SqliteConnection,
    election_id: &str,
    nf: &[u8],
) -> Result<()> {
    sqlx::query(
        "INSERT INTO dnfs(election, hash)
         VALUES ((SELECT id_election FROM elections WHERE id = ?1), ?2)"
    )
    .bind(election_id)
    .bind(nf)
    .execute(&mut *connection)
    .await?;
    Ok(())
}
```

**2. Refactor `store_cmx_root`:**

```rust
// BEFORE
pub async fn store_cmx_root(
    connection: &mut SqliteConnection,
    id_election: u32,
    id_ballot: u32,
    cmx_root: &[u8],
) -> Result<()> {
    sqlx::query(
        "INSERT INTO cmx_roots(election, height, hash)
         VALUES (?1, ?2, ?3)"
    )
    .bind(id_election)
    .bind(id_ballot)
    .bind(cmx_root)
    .execute(&mut *connection)
    .await?;
    Ok(())
}

// AFTER
pub async fn store_cmx_root(
    connection: &mut SqliteConnection,
    election_id: &str,
    id_ballot: u32,
    cmx_root: &[u8],
) -> Result<()> {
    sqlx::query(
        "INSERT INTO cmx_roots(election, height, hash)
         VALUES ((SELECT id_election FROM elections WHERE id = ?1), ?2, ?3)"
    )
    .bind(election_id)
    .bind(id_ballot)
    .bind(cmx_root)
    .execute(&mut *connection)
    .await?;
    Ok(())
}
```

**3. Check for Other Functions:**

Audit the entire `zcash-vote` crate for any other functions that:
- Accept `id_election: u32` as a parameter
- Query tables using `WHERE election = ?` with an integer binding
- May be called from zcash-vote-server or other consumers

Common candidates:
- Any function in `zcash-vote::db` module
- Election loading/initialization functions
- Ballot retrieval functions

**4. Update Database Schema Documentation:**

If zcash-vote creates the `dnfs`, `cmx_roots`, `cmx_frontiers` tables, document that:
- The `election` column is a foreign key to `elections.id_election`
- Calling code should use the TEXT `id` field and resolve via JOIN/subquery
- The INTEGER `id_election` is an internal optimization



---

## Testing Strategy

### Unit Test: Determinism Validation

Add to `src/chain.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::{sqlite::SqliteConnectOptions, SqlitePool};
    
    #[tokio::test]
    async fn test_app_hash_deterministic_regardless_of_insertion_order() {
        // Create two in-memory databases
        // Insert same elections in DIFFERENT orders
        // Verify AppHash is IDENTICAL
        
        // This test MUST pass to prevent regression
    }
}
```

### Integration Test Checklist

- [ ] Deploy to test cluster (4 validators)
- [ ] Insert elections in different orders on different nodes
- [ ] Submit ballots and verify consensus
- [ ] Check all validators reach same block height
- [ ] Verify AppHash matches across all validators
- [ ] Confirm no CheckTx failures

---

