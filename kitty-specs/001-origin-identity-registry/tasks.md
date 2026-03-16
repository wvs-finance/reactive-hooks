# Work Packages: Origin Identity Registry

**Inputs**: Design documents from `kitty-specs/001-origin-identity-registry/`
**Prerequisites**: plan.md (required), spec.md (user stories), invariants.md

**Tests**: Required — this is TDD/type-driven development. Tests are written BEFORE implementation per the project's flow-first methodology.

**Organization**: Fine-grained subtasks (`Txxx`) roll up into work packages (`WPxx`). Each work package must be independently deliverable and testable.

---

## Work Package WP01: Origin Types & Kontrol Proofs (Priority: P0) MVP

**Requirement Refs**: FR-001
**Goal**: Verify the OriginEndpoint type system and originId() function satisfy INV-001 through INV-003 (determinism, injectivity, no zero-image) via Kontrol formal proofs.
**Independent Test**: `kontrol prove` passes for all 3 function-level invariant proofs.
**Prompt**: `tasks/WP01-origin-types-kontrol-proofs.md`
**Estimated size**: ~300 lines

### Included Subtasks
- [x] T001 Write prove_originId_deterministic (INV-001) in `test/kontrol/F1_OriginIdentity.k.sol`
- [x] T002 Run `kontrol build` + `kontrol prove --match-test prove_originId_deterministic`, verify pass
- [x] T003 Write prove_originId_injective (INV-002)
- [x] T004 Run `kontrol prove --match-test prove_originId_injective`, verify pass
- [x] T005 Write prove_originId_no_zero_image (INV-003)
- [x] T006 Run `kontrol prove --match-test prove_originId_no_zero_image`, verify pass

### Implementation Notes
- Each proof is written ONE AT A TIME per TDD skill Phase 4 rules
- Proofs use `prove_` prefix, import KontrolCheats
- Tests MAY use inheritance (`is Test, KontrolCheats`) — only exception to SCOP
- Source files already exist: `src/types/OriginEndpoint.sol`

### Parallel Opportunities
- None — proofs must be sequential (each verified before writing next)

### Dependencies
- None (starting package, types already written)

### Risks & Mitigations
- Kontrol may not be installed → check `kontrol --version` first, fall back to fuzz tests if unavailable
- INV-002 (injectivity) is keccak256 collision resistance — cannot be formally proven, prove for symbolic inputs where at least one field differs

---

## Work Package WP02: Origin Registry Storage & System Proofs (Priority: P0)

**Requirement Refs**: FR-002, FR-003, FR-004, FR-006
**Goal**: Verify the OriginRegistryStorage set/get functions satisfy INV-004 through INV-008 (idempotency, count monotonicity, round-trip, chain-count consistency, no phantoms) via Kontrol proofs and fuzz tests.
**Independent Test**: `kontrol prove` + `forge test` pass for all 5 system-level invariant proofs/tests.
**Prompt**: `tasks/WP02-origin-registry-proofs.md`
**Estimated size**: ~400 lines

### Included Subtasks
- [ ] T007 Write Foundry test harness contract wrapping OriginRegistryStorageMod functions
- [ ] T008 Write prove_registerOrigin_idempotent (INV-004)
- [ ] T009 Run `kontrol prove --match-test prove_registerOrigin_idempotent`, verify pass
- [ ] T010 Write prove_registerOrigin_increments_count (INV-005)
- [ ] T011 Write prove_lookupOrigin_roundtrip (INV-006)
- [ ] T012 Write testFuzz_chain_count_consistency (INV-007) — fuzz test
- [ ] T013 Write prove_no_phantom_origins (INV-008)

### Implementation Notes
- T007 creates a contract that exposes storage functions for testing (inherits Test)
- Proofs written one at a time, each verified before next
- INV-007 uses fuzz testing (random registration sequences, verify sum consistency)
- INV-008 is the critical dual-storage invariant — most important proof

### Parallel Opportunities
- None — sequential proof workflow

### Dependencies
- Depends on WP01 (types must be verified before testing storage)

### Risks & Mitigations
- Namespaced storage may complicate Kontrol symbolic execution → use concrete storage if needed
- INV-008 (no phantoms) requires iterating chain list — may need helper function for proof

---

## Work Package WP03: Static Analysis & F1 Integration Tests (Priority: P1)

**Requirement Refs**: FR-005, FR-007
**Goal**: Run static analysis gate (Slither + Semgrep) on all F1 source files, then write the F1.1–F1.6 Foundry integration tests proving the full flow works end-to-end.
**Independent Test**: Clean Slither/Semgrep output + all 6 F1 test scenarios pass with `forge test`.
**Prompt**: `tasks/WP03-static-analysis-f1-tests.md`
**Estimated size**: ~350 lines

### Included Subtasks
- [ ] T014 Run Slither on `src/types/OriginEndpoint.sol` and `src/modules/OriginRegistryStorageMod.sol`
- [ ] T015 Run Semgrep on same files
- [ ] T016 Fix any findings from T014/T015
- [ ] T017 [P] Write test_F1_1_determinism in `test/F1_OriginIdentity.t.sol`
- [ ] T018 [P] Write test_F1_2_injectivity_eventSig
- [ ] T019 [P] Write test_F1_3_injectivity_chainId
- [ ] T020 [P] Write test_F1_4_injectivity_emitter
- [ ] T021 Write test_F1_5_register_enumerate (register + lookup round-trip + chain enumeration)
- [ ] T022 Write test_F1_6_idempotent_registration

### Implementation Notes
- Static analysis runs FIRST (Phase 5 of TDD skill)
- F1 tests use `test_` prefix (Foundry unit tests, not Kontrol proofs)
- T017-T020 are parallel-safe (independent test functions, same file)
- T021 tests the full flow: register multiple origins, enumerate by chain, verify counts
- T022 verifies double registration produces no change

### Parallel Opportunities
- T017, T018, T019, T020 can be written in parallel (different test functions)
- T014 and T015 can run in parallel (different tools)

### Dependencies
- Depends on WP02 (storage proofs must pass before integration testing)

### Risks & Mitigations
- Slither may flag namespaced storage assembly as "uninitialized storage" → document as false positive
- Semgrep smart contract rules may not cover free-function patterns → note gaps

---

## Dependency & Execution Summary

- **Sequence**: WP01 → WP02 → WP03
- **Parallelization**: Within WP03, static analysis (T014-T016) can run before tests (T017-T022). Test functions T017-T020 are parallel-safe.
- **MVP Scope**: WP01 + WP02 constitute the verified type foundation. WP03 adds the integration test suite.

---

## Subtask Index (Reference)

| Subtask ID | Summary | Work Package | Priority | Parallel? |
|------------|---------|--------------|----------|-----------|
| T001 | prove_originId_deterministic (INV-001) | WP01 | P0 | No |
| T002 | Verify INV-001 proof passes | WP01 | P0 | No |
| T003 | prove_originId_injective (INV-002) | WP01 | P0 | No |
| T004 | Verify INV-002 proof passes | WP01 | P0 | No |
| T005 | prove_originId_no_zero_image (INV-003) | WP01 | P0 | No |
| T006 | Verify INV-003 proof passes | WP01 | P0 | No |
| T007 | Create Foundry test harness contract | WP02 | P0 | No |
| T008 | prove_registerOrigin_idempotent (INV-004) | WP02 | P0 | No |
| T009 | Verify INV-004 proof passes | WP02 | P0 | No |
| T010 | prove_registerOrigin_increments_count (INV-005) | WP02 | P0 | No |
| T011 | prove_lookupOrigin_roundtrip (INV-006) | WP02 | P0 | No |
| T012 | testFuzz_chain_count_consistency (INV-007) | WP02 | P0 | No |
| T013 | prove_no_phantom_origins (INV-008) | WP02 | P0 | No |
| T014 | Run Slither on F1 source files | WP03 | P1 | Yes |
| T015 | Run Semgrep on F1 source files | WP03 | P1 | Yes |
| T016 | Fix static analysis findings | WP03 | P1 | No |
| T017 | test_F1_1_determinism | WP03 | P1 | Yes |
| T018 | test_F1_2_injectivity_eventSig | WP03 | P1 | Yes |
| T019 | test_F1_3_injectivity_chainId | WP03 | P1 | Yes |
| T020 | test_F1_4_injectivity_emitter | WP03 | P1 | Yes |
| T021 | test_F1_5_register_enumerate | WP03 | P1 | No |
| T022 | test_F1_6_idempotent_registration | WP03 | P1 | No |
