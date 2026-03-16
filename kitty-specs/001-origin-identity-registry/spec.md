# Feature Specification: Origin Identity Registry

**Feature Branch**: `001-origin-identity-registry`
**Created**: 2026-03-16
**Status**: Draft
**Input**: F1 flow from EDT design — type system and registry for origin endpoints with deterministic hashing and hierarchical enumeration.

## User Scenarios & Testing

### User Story 1 - Compute Deterministic Origin ID (Priority: P1)

A reactive contract developer creates an `OriginEndpoint` from a chain ID, emitter address, and event signature, and computes a deterministic `originId` hash. The same inputs always produce the same ID. Different inputs always produce different IDs.

**Why this priority**: Every subsequent EDT flow (bind, dispatch, fan-out, pause, unbind) depends on origin identity being correct and collision-free. This is the foundation.

**Independent Test**: Can be fully tested with pure function calls — no storage, no state, no external dependencies. Delivers the core identity primitive.

**Acceptance Scenarios**:

1. **Given** an OriginEndpoint(chainId=1, emitter=0xAAA, eventSig=SWAP_SIG), **When** `originId()` is called twice with the same inputs, **Then** both results are identical (determinism).
2. **Given** two OriginEndpoints differing only in eventSig, **When** `originId()` is called on each, **Then** results differ (injectivity).
3. **Given** two OriginEndpoints differing only in chainId, **When** `originId()` is called on each, **Then** results differ (injectivity).
4. **Given** two OriginEndpoints differing only in emitter address, **When** `originId()` is called on each, **Then** results differ (injectivity).

---

### User Story 2 - Register and Lookup Origins (Priority: P1)

A reactive contract developer registers origin endpoints and retrieves them later by their deterministic hash, confirming the stored struct matches the original input (round-trip integrity).

**Why this priority**: Registration + lookup is required before any binding can reference an origin. Without this, bind() has nothing to bind to.

**Independent Test**: Can be tested with a Foundry test harness contract that wraps the storage functions. Delivers the registry primitive.

**Acceptance Scenarios**:

1. **Given** a registered OriginEndpoint, **When** `lookupOrigin(originId)` is called, **Then** the returned struct matches the original (round-trip).
2. **Given** the same OriginEndpoint registered twice, **When** the second registration occurs, **Then** no revert and the origin count remains 1 (idempotent).
3. **Given** an unregistered originId, **When** `lookupOrigin(fakeId)` is called, **Then** it reverts or returns a zero/sentinel value indicating absence.

---

### User Story 3 - Enumerate Origins by Chain (Priority: P2)

A reactive contract developer queries all registered origins for a specific chain ID, enabling introspection and administrative tooling.

**Why this priority**: Enumeration supports dispatch routing (F7), administrative UIs, and debugging. Not blocking for core bind/unbind flows but needed for production.

**Independent Test**: Can be tested by registering multiple origins across chains and verifying per-chain counts and contents.

**Acceptance Scenarios**:

1. **Given** 2 origins registered on chain 1 and 1 origin on chain 42161, **When** `getOriginsByChain(1)` is called, **Then** returns 2 entries.
2. **Given** the same state, **When** `getOriginsByChain(42161)` is called, **Then** returns 1 entry.
3. **Given** no origins registered on chain 999, **When** `getOriginsByChain(999)` is called, **Then** returns 0 entries.

### Edge Cases

- What happens when `originId` is computed with `emitter = address(0)`? Should this be a valid origin or rejected?
- What happens when `eventSig = bytes32(0)`? This could represent a wildcard subscription (REACTIVE_IGNORE pattern) — should the registry accept it?
- What is the maximum number of origins per chain before gas costs become prohibitive? (Linked list traversal in F7)

## Requirements

### Functional Requirements

- **FR-001**: System MUST compute a deterministic `bytes32` origin ID from `(uint32 chainId, address emitter, bytes32 eventSig)` using `keccak256`.
- **FR-002**: System MUST store origin endpoints in a dual representation: hash-indexed for O(1) lookup AND chain-indexed for enumeration.
- **FR-003**: System MUST support idempotent registration — registering the same origin twice produces no revert and no duplicate entry.
- **FR-004**: System MUST support round-trip lookup — `lookupOrigin(originId(endpoint))` returns the original `OriginEndpoint` struct.
- **FR-005**: System MUST support enumeration by chain ID — `getOriginsByChain(chainId)` returns all origins registered for that chain.
- **FR-006**: System MUST use namespaced storage (keccak256 slot isolation) compatible with the existing Compose/Mod pattern used in the codebase.
- **FR-007**: System MUST use file-level free functions (SCOP — no `library` keyword, no inheritance, no modifiers).

### Key Entities

- **OriginEndpoint**: Represents an event source on a specific chain. Attributes: chainId (uint32), emitter (address), eventSig (bytes32).
- **originId**: A deterministic bytes32 hash derived from an OriginEndpoint. Used as the primary key for O(1) lookups and binding references.
- **OriginRegistryStorage**: The dual-representation storage struct containing both hash→struct mapping and chainId→list mapping.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All 6 test scenarios (F1.1–F1.6) pass in Foundry.
- **SC-002**: `originId()` is a pure function with zero storage reads/writes.
- **SC-003**: `registerOrigin()` + `lookupOrigin()` round-trips correctly for any valid OriginEndpoint.
- **SC-004**: Duplicate registration does not increase origin count.
- **SC-005**: Per-chain enumeration returns correct count and contents for all registered chains.
- **SC-006**: All code follows SCOP conventions (no library keyword, no inheritance, no modifiers, file-level free functions).
