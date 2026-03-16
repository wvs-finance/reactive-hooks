---
work_package_id: "WP03"
subtasks:
  - "T014"
  - "T015"
  - "T016"
  - "T017"
  - "T018"
  - "T019"
  - "T020"
  - "T021"
  - "T022"
title: "Static Analysis & F1 Integration Tests"
phase: "Phase 5-6 - Static Analysis Gate & Implementation Tests"
lane: "planned"
assignee: ""
agent: ""
shell_pid: ""
review_status: ""
reviewed_by: ""
dependencies: ["WP02"]
requirement_refs: ["FR-005", "FR-007"]
history:
  - timestamp: "2026-03-16T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP03 – Static Analysis & F1 Integration Tests

## Review Feedback

*[This section is empty initially.]*

---

## Objectives & Success Criteria

- Clean Slither and Semgrep output on all F1 source files
- All 6 F1 test scenarios (F1.1–F1.6) pass with `forge test`
- Every invariant from Phase 2 covered by at least one proof or fuzz test (verification phase complete)

**Implementation command**: `spec-kitty implement WP03 --base WP02`

## Context & Constraints

- **Source files**: `src/types/OriginEndpoint.sol`, `src/modules/OriginRegistryStorageMod.sol`
- **Depends on**: WP02 (Kontrol proofs must pass before integration testing)
- **TDD skill Phase 5**: Static analysis BEFORE implementation tests
- **Flows reference**: `refs/edt-flows.md` (F1.1–F1.6 test scenarios)
- **SCOP**: Test contracts MAY use inheritance

## Subtasks & Detailed Guidance

### Subtask T014 – Run Slither on F1 source files

- **Purpose**: Static analysis gate — catch vulnerabilities before integration testing.
- **Steps**:
  1. Run: `slither src/types/OriginEndpoint.sol --filter-paths "test/"`
  2. Run: `slither src/modules/OriginRegistryStorageMod.sol --filter-paths "test/"`
  3. Document all findings
- **Files**: None (analysis step)
- **Parallel?**: Yes (can run alongside T015)
- **Notes**: Expect possible false positives on assembly blocks in namespaced storage. Document these.

### Subtask T015 – Run Semgrep on F1 source files

- **Purpose**: Additional static analysis with smart contract security rules.
- **Steps**:
  1. Run: `semgrep --config https://github.com/Decurity/semgrep-smart-contracts --metrics=off src/types/OriginEndpoint.sol src/modules/OriginRegistryStorageMod.sol`
  2. Document all findings
- **Files**: None (analysis step)
- **Parallel?**: Yes (can run alongside T014)
- **Notes**: Free-function patterns may not be covered by standard rules. Note gaps.

### Subtask T016 – Fix static analysis findings

- **Purpose**: Address all Slither/Semgrep findings before proceeding to tests.
- **Steps**:
  1. For each finding: fix, document as false positive, or justify exception
  2. Re-run both tools to verify clean output
- **Files**: `src/types/OriginEndpoint.sol`, `src/modules/OriginRegistryStorageMod.sol` (if changes needed)
- **Parallel?**: No (depends on T014, T015)

### Subtask T017 – Write test_F1_1_determinism

- **Purpose**: F1.1 integration test — verify originId produces identical results for identical inputs.
- **Steps**:
  1. Create `test/F1_OriginIdentity.t.sol`
  2. Write test with concrete values:
     ```solidity
     function test_F1_1_determinism() public pure {
         OriginEndpoint memory a = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
         OriginEndpoint memory b = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
         assertEq(a.originId(), b.originId());
     }
     ```
- **Files**: `test/F1_OriginIdentity.t.sol` (new file)
- **Parallel?**: Yes (independent test function)

### Subtask T018 – Write test_F1_2_injectivity_eventSig

- **Purpose**: F1.2 — different eventSig produces different originId.
- **Steps**:
  ```solidity
  function test_F1_2_injectivity_eventSig() public pure {
      OriginEndpoint memory a = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
      OriginEndpoint memory b = OriginEndpoint(1, address(0xAAA), MINT_SIG);
      assertTrue(a.originId() != b.originId());
  }
  ```
- **Files**: `test/F1_OriginIdentity.t.sol`
- **Parallel?**: Yes

### Subtask T019 – Write test_F1_3_injectivity_chainId

- **Purpose**: F1.3 — different chainId produces different originId.
- **Steps**:
  ```solidity
  function test_F1_3_injectivity_chainId() public pure {
      OriginEndpoint memory a = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
      OriginEndpoint memory b = OriginEndpoint(42161, address(0xAAA), SWAP_SIG);
      assertTrue(a.originId() != b.originId());
  }
  ```
- **Files**: `test/F1_OriginIdentity.t.sol`
- **Parallel?**: Yes

### Subtask T020 – Write test_F1_4_injectivity_emitter

- **Purpose**: F1.4 — different emitter produces different originId.
- **Steps**:
  ```solidity
  function test_F1_4_injectivity_emitter() public pure {
      OriginEndpoint memory a = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
      OriginEndpoint memory b = OriginEndpoint(1, address(0xBBB), SWAP_SIG);
      assertTrue(a.originId() != b.originId());
  }
  ```
- **Files**: `test/F1_OriginIdentity.t.sol`
- **Parallel?**: Yes

### Subtask T021 – Write test_F1_5_register_enumerate

- **Purpose**: F1.5 — register multiple origins, verify enumeration by chain and round-trip lookup.
- **Steps**:
  ```solidity
  function test_F1_5_register_enumerate() public {
      OriginRegistryStorage storage s = _originRegistryStorage();

      OriginEndpoint memory e1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
      OriginEndpoint memory e2 = OriginEndpoint(1, address(0xAAA), MINT_SIG);
      OriginEndpoint memory e3 = OriginEndpoint(42161, address(0xBBB), SWAP_SIG);

      setOrigin(s, e1);
      setOrigin(s, e2);
      setOrigin(s, e3);

      // Chain 1: 2 entries
      assertEq(getOriginCountByChain(s, 1), 2);
      // Chain 42161: 1 entry
      assertEq(getOriginCountByChain(s, 42161), 1);
      // Total: 3
      assertEq(getOriginTotalCount(s), 3);

      // Round-trip lookup
      OriginEndpoint storage stored = getOrigin(s, e1.originId());
      assertEq(stored.chainId, 1);
      assertEq(stored.emitter, address(0xAAA));
      assertEq(stored.eventSig, SWAP_SIG);
  }
  ```
- **Files**: `test/F1_OriginIdentity.t.sol`
- **Parallel?**: No (depends on storage, complex test)

### Subtask T022 – Write test_F1_6_idempotent_registration

- **Purpose**: F1.6 — double registration produces no revert and no duplicate.
- **Steps**:
  ```solidity
  function test_F1_6_idempotent_registration() public {
      OriginRegistryStorage storage s = _originRegistryStorage();
      OriginEndpoint memory e = OriginEndpoint(1, address(0xAAA), SWAP_SIG);

      bytes32 id1 = setOrigin(s, e);
      bytes32 id2 = setOrigin(s, e);

      assertEq(id1, id2);
      assertEq(getOriginCountByChain(s, 1), 1);
      assertEq(getOriginTotalCount(s), 1);
  }
  ```
- **Files**: `test/F1_OriginIdentity.t.sol`
- **Parallel?**: No

## Test Strategy

```bash
# Static analysis first
slither src/types/OriginEndpoint.sol src/modules/OriginRegistryStorageMod.sol --filter-paths "test/"
semgrep --config https://github.com/Decurity/semgrep-smart-contracts --metrics=off src/types/ src/modules/

# Then integration tests
forge test --match-path test/F1_OriginIdentity.t.sol -vvv
```

## Risks & Mitigations

- **Slither on free functions**: May not fully support file-level free functions. Document coverage gaps.
- **Storage isolation in tests**: Each test function gets fresh EVM state in Foundry, so storage tests are naturally isolated. No setUp() needed for most tests.
- **Event signature constants**: Define `SWAP_SIG` and `MINT_SIG` as test constants matching existing V3 event signatures from the codebase.

## Review Guidance

- Verify test names match F1.1–F1.6 from `refs/edt-flows.md`
- Verify static analysis ran on ALL F1 source files
- Verify no business logic was added to source files (only tests in this WP)
- Verify all 10 invariants are now covered: INV-001–003 (WP01 proofs), INV-004–008 (WP02 proofs), INV-009–010 (compile-time/review)

## Activity Log

- 2026-03-16T12:00:00Z – system – lane=planned – Prompt created.
