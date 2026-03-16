# Invariants: Origin Identity Registry

## Function-Level Invariants

| ID | INV-001 |
|---|---|
| Description | originId is a pure deterministic function — same inputs always produce same output |
| Category | Function-level |
| Hoare Triple | {true} → originId(e) == originId(e') where e.chainId==e'.chainId ∧ e.emitter==e'.emitter ∧ e.eventSig==e'.eventSig → {result_1 == result_2} |
| Affected | OriginEndpoint type, originId() free function |
| Verification | Kontrol proof |

| ID | INV-002 |
|---|---|
| Description | originId is injective — distinct inputs produce distinct outputs (no collisions) |
| Category | Function-level |
| Hoare Triple | {e.chainId != e'.chainId ∨ e.emitter != e'.emitter ∨ e.eventSig != e'.eventSig} → originId(e), originId(e') → {result_1 != result_2} |
| Affected | OriginEndpoint type, originId() free function |
| Verification | Kontrol proof (symbolic — for all possible inputs where at least one field differs) |

| ID | INV-003 |
|---|---|
| Description | originId has no zero-image — no valid OriginEndpoint maps to bytes32(0) |
| Category | Function-level |
| Hoare Triple | {true} → originId(e) → {result != bytes32(0)} |
| Affected | originId() free function |
| Verification | Kontrol proof |
| Notes | bytes32(0) is used as sentinel for "not found" in lookups. If originId could return 0, lookups would be ambiguous. |

## System-Level Invariants

| ID | INV-004 |
|---|---|
| Description | Registration is idempotent — registering the same origin twice does not change state |
| Category | System-level |
| Hoare Triple | {exists[id] == true ∧ count == n} → registerOrigin(e) where originId(e)==id → {exists[id] == true ∧ count == n} |
| Affected | OriginRegistryLib.registerOrigin(), OriginRegistryStorage |
| Verification | Kontrol proof + fuzz test |

| ID | INV-005 |
|---|---|
| Description | Registration monotonically increases count — a new origin increments count by exactly 1 |
| Category | System-level |
| Hoare Triple | {exists[id] == false ∧ countByChain[chainId] == n ∧ totalCount == m} → registerOrigin(e) → {exists[id] == true ∧ countByChain[chainId] == n+1 ∧ totalCount == m+1} |
| Affected | OriginRegistryLib.registerOrigin(), OriginRegistryStorage |
| Verification | Kontrol proof + fuzz test |

| ID | INV-006 |
|---|---|
| Description | Round-trip integrity — lookupOrigin(originId(e)) returns e for any registered origin |
| Category | System-level |
| Hoare Triple | {registered(e)} → lookupOrigin(originId(e)) → {result.chainId == e.chainId ∧ result.emitter == e.emitter ∧ result.eventSig == e.eventSig} |
| Affected | OriginRegistryLib.registerOrigin(), OriginRegistryLib.lookupOrigin(), OriginRegistryStorage |
| Verification | Kontrol proof |

| ID | INV-007 |
|---|---|
| Description | Chain-count consistency — sum of all per-chain counts equals total registered origin count |
| Category | System-level |
| Hoare Triple | {true} → any sequence of registerOrigin() calls → {Σ countByChain[c] for all c == totalCount} |
| Affected | OriginRegistryStorage |
| Verification | Fuzz test (enumerate all chains after random registrations) |

| ID | INV-008 |
|---|---|
| Description | No phantom origins — an origin appears in chain enumeration if and only if it exists in the hash lookup |
| Category | System-level |
| Hoare Triple | {true} → any state → {∀ id: inChainList(id, chainId) ⟺ exists[id] == true ∧ origins[id].chainId == chainId} |
| Affected | OriginRegistryStorage (dual representation consistency) |
| Verification | Kontrol proof + fuzz test |
| Notes | This is the critical dual-storage invariant. If the hash map and chain list diverge, the registry is corrupt. |

## Type-Level Invariants

| ID | INV-009 |
|---|---|
| Description | OriginEndpoint uses uint32 for chainId — enforced by construction, no chain ID exceeds 2^32-1 |
| Category | Type-level |
| Hoare Triple | N/A — enforced by Solidity compiler (uint32 type) |
| Affected | OriginEndpoint struct |
| Verification | Compile-time |

| ID | INV-010 |
|---|---|
| Description | originId is the ONLY way to derive an origin's identity — no alternate ID computation exists |
| Category | Type-level |
| Hoare Triple | N/A — enforced by API design (single free function, no public wrap/unwrap) |
| Affected | originId() free function |
| Verification | Code review + static analysis |
| Notes | If multiple ID derivation paths exist, bindings could reference the same origin under different IDs, breaking fan-out dispatch. |

## Summary

| Category | Count | IDs |
|---|---|---|
| Function-level | 3 | INV-001, INV-002, INV-003 |
| System-level | 5 | INV-004, INV-005, INV-006, INV-007, INV-008 |
| Type-level | 2 | INV-009, INV-010 |
| **Total** | **10** | |
