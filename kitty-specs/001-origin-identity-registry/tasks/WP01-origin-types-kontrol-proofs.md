---
work_package_id: "WP01"
subtasks:
  - "T001"
  - "T002"
  - "T003"
  - "T004"
  - "T005"
  - "T006"
title: "Origin Types & Kontrol Proofs"
phase: "Phase 4 - Scaffold Kontrol Proofs"
lane: "planned"
assignee: ""
agent: ""
shell_pid: ""
review_status: ""
reviewed_by: ""
dependencies: []
requirement_refs: ["FR-001"]
history:
  - timestamp: "2026-03-16T12:00:00Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP01 – Origin Types & Kontrol Proofs

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

- Formally verify the 3 function-level invariants (INV-001, INV-002, INV-003) for `originId()` via Kontrol proofs
- All proofs pass `kontrol prove`
- Each proof written and verified ONE AT A TIME before writing the next

**Implementation command**: `spec-kitty implement WP01`

## Context & Constraints

- **Source file**: `src/types/OriginEndpoint.sol` (already exists)
- **SCOP rules**: No `library` keyword, no inheritance (EXCEPT test contracts), no modifiers
- **TDD skill Phase 4**: Write ONE proof → build → prove → verify → user review → THEN next proof
- **Invariants doc**: `kitty-specs/001-origin-identity-registry/invariants.md`
- **Flows reference**: `refs/edt-flows.md` (F1 flow definition)

### originId() implementation (reference)

```solidity
function originId(OriginEndpoint memory self) pure returns (bytes32) {
    return keccak256(abi.encodePacked(self.chainId, self.emitter, self.eventSig));
}
```

## Subtasks & Detailed Guidance

### Subtask T001 – Write prove_originId_deterministic (INV-001)

- **Purpose**: Verify that `originId()` is a pure deterministic function — same inputs always produce the same output.
- **Steps**:
  1. Create `test/kontrol/F1_OriginIdentity.k.sol`
  2. Import `OriginEndpoint` type and `originId` function
  3. Write proof:
     ```solidity
     function prove_originId_deterministic(
         uint32 chainId,
         address emitter,
         bytes32 eventSig
     ) public pure {
         OriginEndpoint memory a = OriginEndpoint(chainId, emitter, eventSig);
         OriginEndpoint memory b = OriginEndpoint(chainId, emitter, eventSig);
         assert(a.originId() == b.originId());
     }
     ```
- **Files**: `test/kontrol/F1_OriginIdentity.k.sol` (new file)
- **Parallel?**: No
- **Notes**: This is the simplest proof — establishes that the test infrastructure works.

### Subtask T002 – Verify INV-001 proof passes

- **Purpose**: Run Kontrol and verify the determinism proof passes.
- **Steps**:
  1. Run `kontrol build`
  2. Run `kontrol prove --match-test prove_originId_deterministic`
  3. If pass: proceed to T003
  4. If fail: debug, fix, re-run
- **Files**: None (verification step)
- **Notes**: If Kontrol is not installed, fall back to `forge test --match-test prove_originId_deterministic` as a sanity check (Foundry will run it as a regular test without symbolic execution).

### Subtask T003 – Write prove_originId_injective (INV-002)

- **Purpose**: Verify that distinct inputs produce distinct outputs (no collisions).
- **Steps**:
  1. Add proof to `test/kontrol/F1_OriginIdentity.k.sol`:
     ```solidity
     function prove_originId_injective_chainId(
         uint32 chainId1,
         uint32 chainId2,
         address emitter,
         bytes32 eventSig
     ) public pure {
         vm.assume(chainId1 != chainId2);
         OriginEndpoint memory a = OriginEndpoint(chainId1, emitter, eventSig);
         OriginEndpoint memory b = OriginEndpoint(chainId2, emitter, eventSig);
         assert(a.originId() != b.originId());
     }

     function prove_originId_injective_emitter(
         uint32 chainId,
         address emitter1,
         address emitter2,
         bytes32 eventSig
     ) public pure {
         vm.assume(emitter1 != emitter2);
         OriginEndpoint memory a = OriginEndpoint(chainId, emitter1, eventSig);
         OriginEndpoint memory b = OriginEndpoint(chainId, emitter2, eventSig);
         assert(a.originId() != b.originId());
     }

     function prove_originId_injective_eventSig(
         uint32 chainId,
         address emitter,
         bytes32 eventSig1,
         bytes32 eventSig2
     ) public pure {
         vm.assume(eventSig1 != eventSig2);
         OriginEndpoint memory a = OriginEndpoint(chainId, emitter, eventSig1);
         OriginEndpoint memory b = OriginEndpoint(chainId, emitter, eventSig2);
         assert(a.originId() != b.originId());
     }
     ```
  2. Three separate proofs — one per field that can differ
- **Files**: `test/kontrol/F1_OriginIdentity.k.sol`
- **Parallel?**: No
- **Notes**: Injectivity for keccak256 with `encodePacked` depends on no ABI encoding collisions. Since `uint32` (4 bytes) + `address` (20 bytes) + `bytes32` (32 bytes) = 56 bytes fixed-length, there's no ambiguity in the packed encoding. Kontrol should verify this symbolically.

### Subtask T004 – Verify INV-002 proofs pass

- **Purpose**: Run Kontrol and verify all 3 injectivity proofs pass.
- **Steps**:
  1. Run `kontrol prove --match-test prove_originId_injective`
  2. All 3 proofs should pass
  3. If any fail: investigate — likely an encodePacked collision edge case
- **Files**: None (verification step)

### Subtask T005 – Write prove_originId_no_zero_image (INV-003)

- **Purpose**: Verify that no valid OriginEndpoint maps to bytes32(0). This ensures bytes32(0) is safe to use as a "not found" sentinel.
- **Steps**:
  1. Add proof to `test/kontrol/F1_OriginIdentity.k.sol`:
     ```solidity
     function prove_originId_no_zero_image(
         uint32 chainId,
         address emitter,
         bytes32 eventSig
     ) public pure {
         OriginEndpoint memory e = OriginEndpoint(chainId, emitter, eventSig);
         assert(e.originId() != bytes32(0));
     }
     ```
- **Files**: `test/kontrol/F1_OriginIdentity.k.sol`
- **Parallel?**: No
- **Notes**: This proves that keccak256 of any 56-byte input is never zero. Kontrol should verify this via exhaustive symbolic search over the input space.

### Subtask T006 – Verify INV-003 proof passes

- **Purpose**: Run Kontrol and verify the no-zero-image proof passes.
- **Steps**:
  1. Run `kontrol prove --match-test prove_originId_no_zero_image`
  2. If pass: WP01 complete
  3. If fail: investigate — extremely unlikely for keccak256

## Test Strategy

All tests in this WP are Kontrol formal verification proofs (`prove_` prefix). They verify properties symbolically over ALL possible inputs, not just specific test vectors.

**Commands**:
```bash
kontrol build
kontrol prove --match-test prove_originId_deterministic
kontrol prove --match-test prove_originId_injective
kontrol prove --match-test prove_originId_no_zero_image
```

**Fallback** (if Kontrol unavailable):
```bash
forge test --match-test prove_ -vvv
```

## Risks & Mitigations

- **Kontrol not installed**: Fall back to `forge test` which runs proofs as regular fuzz tests (less coverage but still valuable)
- **INV-002 timeout**: Symbolic keccak256 collision analysis may be computationally expensive. If Kontrol times out, use `--smt-timeout 600` or split into smaller proofs.
- **encodePacked collision risk**: Fixed-length encoding (4+20+32=56 bytes) eliminates ABI ambiguity. No dynamic types involved.

## Review Guidance

- Verify each proof maps exactly to its invariant (INV-001, INV-002, INV-003)
- Verify proofs use symbolic inputs (no hardcoded values except in `vm.assume`)
- Verify test file follows SCOP exceptions (inheritance only for Test/KontrolCheats)
- Verify proofs were run one at a time (check activity log)

## Activity Log

- 2026-03-16T12:00:00Z – system – lane=planned – Prompt created.
