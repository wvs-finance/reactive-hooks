---
work_package_id: WP02
title: Origin Registry Storage & System Proofs
lane: "doing"
dependencies: [WP01]
base_branch: 001-origin-identity-registry-WP01
base_commit: 330991e3a3b060d9acd84b160554f11870d38c8f
created_at: '2026-03-16T12:19:42.057615+00:00'
subtasks:
- T007
- T008
- T009
- T010
- T011
- T012
- T013
phase: Phase 4 - Scaffold Kontrol Proofs
assignee: ''
agent: ''
shell_pid: "60179"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-03-16T12:00:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
requirement_refs: [FR-002, FR-003, FR-004, FR-006]
---

# Work Package Prompt: WP02 – Origin Registry Storage & System Proofs

## Review Feedback

*[This section is empty initially.]*

---

## Objectives & Success Criteria

- Create Foundry test harness wrapping OriginRegistryStorageMod functions
- Formally verify 4 system-level invariants (INV-004, INV-005, INV-006, INV-008) via Kontrol
- Fuzz test 1 system-level invariant (INV-007) via Foundry
- All proofs/tests pass

**Implementation command**: `spec-kitty implement WP02 --base WP01`

## Context & Constraints

- **Source files**: `src/types/OriginEndpoint.sol`, `src/modules/OriginRegistryStorageMod.sol` (both exist)
- **Depends on**: WP01 (function-level invariants verified)
- **SCOP**: Test harness contract MAY use inheritance (`is Test, KontrolCheats`)
- **TDD skill Phase 4**: One proof at a time, verify, then next
- **Invariants doc**: `kitty-specs/001-origin-identity-registry/invariants.md`

## Subtasks & Detailed Guidance

### Subtask T007 – Create Foundry test harness contract

- **Purpose**: Wrap storage-level free functions so Foundry/Kontrol can call them via a contract.
- **Steps**:
  1. Create `test/kontrol/F1_OriginRegistry.k.sol`
  2. Import OriginEndpoint, OriginRegistryStorage, and all free functions from OriginRegistryStorageMod
  3. Create contract:
     ```solidity
     contract F1_OriginRegistryProof is Test, KontrolCheats {
         function _store() internal pure returns (OriginRegistryStorage storage) {
             return _originRegistryStorage();
         }

         // Wrapper functions for each storage operation
         function registerOrigin(uint32 chainId, address emitter, bytes32 eventSig) external returns (bytes32) {
             OriginEndpoint memory e = OriginEndpoint(chainId, emitter, eventSig);
             return setOrigin(_store(), e);
         }

         function lookupOrigin(bytes32 id) external view returns (OriginEndpoint memory) {
             return getOrigin(_store(), id);
         }

         function originExists(bytes32 id) external view returns (bool) {
             return getOriginExists(_store(), id);
         }

         function countByChain(uint32 chainId) external view returns (uint256) {
             return getOriginCountByChain(_store(), chainId);
         }

         function totalCount() external view returns (uint256) {
             return getOriginTotalCount(_store());
         }
     }
     ```
- **Files**: `test/kontrol/F1_OriginRegistry.k.sol` (new file)
- **Notes**: This contract exists ONLY for testing. It wraps free functions into callable external functions.

### Subtask T008 – Write prove_registerOrigin_idempotent (INV-004)

- **Purpose**: Verify that registering the same origin twice does not change state.
- **Steps**:
  1. Add proof to the harness contract:
     ```solidity
     function prove_registerOrigin_idempotent(
         uint32 chainId,
         address emitter,
         bytes32 eventSig
     ) public {
         OriginEndpoint memory e = OriginEndpoint(chainId, emitter, eventSig);
         OriginRegistryStorage storage s = _store();

         bytes32 id1 = setOrigin(s, e);
         uint256 countAfterFirst = s.totalCount;
         bool existsAfterFirst = s.exists[id1];

         bytes32 id2 = setOrigin(s, e);
         uint256 countAfterSecond = s.totalCount;
         bool existsAfterSecond = s.exists[id2];

         assert(id1 == id2);
         assert(countAfterFirst == countAfterSecond);
         assert(existsAfterFirst && existsAfterSecond);
     }
     ```
- **Files**: `test/kontrol/F1_OriginRegistry.k.sol`

### Subtask T009 – Verify INV-004 proof passes

- **Steps**: `kontrol prove --match-test prove_registerOrigin_idempotent`

### Subtask T010 – Write prove_registerOrigin_increments_count (INV-005)

- **Purpose**: Verify a new origin increments totalCount by exactly 1 and chain count by exactly 1.
- **Steps**:
  1. Add proof:
     ```solidity
     function prove_registerOrigin_increments_count(
         uint32 chainId,
         address emitter,
         bytes32 eventSig
     ) public {
         OriginRegistryStorage storage s = _store();
         OriginEndpoint memory e = OriginEndpoint(chainId, emitter, eventSig);
         bytes32 id = e.originId();

         vm.assume(!s.exists[id]); // ensure it's genuinely new

         uint256 totalBefore = s.totalCount;
         uint256 chainBefore = getOriginCountByChain(s, chainId);

         setOrigin(s, e);

         assert(s.totalCount == totalBefore + 1);
         assert(getOriginCountByChain(s, chainId) == chainBefore + 1);
     }
     ```
- **Files**: `test/kontrol/F1_OriginRegistry.k.sol`

### Subtask T011 – Write prove_lookupOrigin_roundtrip (INV-006)

- **Purpose**: Verify that `getOrigin(setOrigin(e))` returns the original OriginEndpoint.
- **Steps**:
  1. Add proof:
     ```solidity
     function prove_lookupOrigin_roundtrip(
         uint32 chainId,
         address emitter,
         bytes32 eventSig
     ) public {
         OriginRegistryStorage storage s = _store();
         OriginEndpoint memory e = OriginEndpoint(chainId, emitter, eventSig);

         bytes32 id = setOrigin(s, e);
         OriginEndpoint storage stored = getOrigin(s, id);

         assert(stored.chainId == chainId);
         assert(stored.emitter == emitter);
         assert(stored.eventSig == eventSig);
     }
     ```
- **Files**: `test/kontrol/F1_OriginRegistry.k.sol`

### Subtask T012 – Write testFuzz_chain_count_consistency (INV-007)

- **Purpose**: Verify that sum of per-chain counts equals totalCount after random registrations.
- **Steps**:
  1. Add fuzz test (not Kontrol — uses `testFuzz_` prefix):
     ```solidity
     function testFuzz_chain_count_consistency(
         uint32[5] memory chainIds,
         address[5] memory emitters,
         bytes32[5] memory eventSigs
     ) public {
         OriginRegistryStorage storage s = _store();
         uint32[] memory seenChains = new uint32[](5);
         uint256 seenCount = 0;

         for (uint256 i = 0; i < 5; i++) {
             OriginEndpoint memory e = OriginEndpoint(chainIds[i], emitters[i], eventSigs[i]);
             setOrigin(s, e);

             // Track unique chains
             bool found = false;
             for (uint256 j = 0; j < seenCount; j++) {
                 if (seenChains[j] == chainIds[i]) { found = true; break; }
             }
             if (!found) { seenChains[seenCount] = chainIds[i]; seenCount++; }
         }

         // Sum per-chain counts
         uint256 sum = 0;
         for (uint256 i = 0; i < seenCount; i++) {
             sum += getOriginCountByChain(s, seenChains[i]);
         }

         assert(sum == getOriginTotalCount(s));
     }
     ```
- **Files**: `test/kontrol/F1_OriginRegistry.k.sol`
- **Notes**: Uses `testFuzz_` prefix — Foundry fuzz test, not Kontrol symbolic proof. Run with `forge test --match-test testFuzz_chain_count_consistency`.

### Subtask T013 – Write prove_no_phantom_origins (INV-008)

- **Purpose**: Verify that an origin appears in the chain list if and only if it exists in the hash lookup (dual-storage consistency).
- **Steps**:
  1. Add proof:
     ```solidity
     function prove_no_phantom_origins(
         uint32 chainId,
         address emitter,
         bytes32 eventSig
     ) public {
         OriginRegistryStorage storage s = _store();
         OriginEndpoint memory e = OriginEndpoint(chainId, emitter, eventSig);
         bytes32 id = e.originId();

         // Before registration: not in hash map, not in chain list
         assert(!getOriginExists(s, id));
         assert(getOriginCountByChain(s, chainId) == 0);

         // After registration: in hash map AND in chain list
         setOrigin(s, e);
         assert(getOriginExists(s, id));
         assert(getOriginCountByChain(s, chainId) == 1);
         assert(getOriginIdByChainAt(s, chainId, 0) == id);
     }
     ```
- **Files**: `test/kontrol/F1_OriginRegistry.k.sol`
- **Notes**: This is the critical dual-storage invariant. If this proof passes, the registry cannot have phantom entries.

## Test Strategy

**Kontrol proofs**: INV-004, INV-005, INV-006, INV-008
```bash
kontrol build
kontrol prove --match-test prove_registerOrigin_idempotent
kontrol prove --match-test prove_registerOrigin_increments_count
kontrol prove --match-test prove_lookupOrigin_roundtrip
kontrol prove --match-test prove_no_phantom_origins
```

**Fuzz test**: INV-007
```bash
forge test --match-test testFuzz_chain_count_consistency -vvv
```

## Risks & Mitigations

- **Storage symbolic execution**: Kontrol may struggle with storage-heavy proofs (mappings, arrays). Use `--smt-timeout 600` or increase memory.
- **Array push in proof**: `originsByChain[].push()` may be hard to reason about symbolically. If INV-008 times out, simplify to single-registration case.
- **Namespaced storage**: The `assembly { s.slot := ... }` pattern should be transparent to Kontrol, but verify.

## Review Guidance

- Verify each proof maps to its invariant (INV-004 through INV-008)
- Verify test harness doesn't add business logic (pure wrappers only)
- Verify fuzz test (INV-007) covers meaningful input space (5 registrations, varying chains)
- Verify proofs were sequential (activity log)

## Activity Log

- 2026-03-16T12:00:00Z – system – lane=planned – Prompt created.
