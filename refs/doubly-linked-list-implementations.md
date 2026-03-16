# Doubly-Linked List Implementations in Solidity: Research Report

## Executive Summary

This report evaluates open-source Solidity doubly-linked list (DLL) implementations for use in the reactive-hooks project. The project requires a DLL that works with namespaced storage (keccak256 slot isolation), supports O(1) insert/remove, allows iteration with skip semantics for paused entries, stores bytes32 node IDs, and is compatible with Foundry and Solidity >=0.8.26.

After evaluating six known implementations and checking major utility libraries (solady, OpenZeppelin, PRBMath), the recommendation is to **write a custom implementation** using vittominacori/solidity-linked-list as the primary structural reference, adapted for namespaced storage and the project's free-function + storage-pointer conventions.

---

## 1. Implementations Evaluated

### 1.1 vittominacori/solidity-linked-list (StructuredLinkedList)

- **Repository**: https://github.com/vittominacori/solidity-linked-list
- **License**: MIT
- **Solidity version**: ^0.8.0 (compatible with >=0.8.26)
- **Last maintained**: Actively maintained as of 2024

#### Storage Layout

```solidity
struct List {
    uint256 size;                                    // 1 slot
    mapping(uint256 => mapping(bool => uint256)) list; // nested mapping: node => (PREV|NEXT => neighbor)
}
```

- **Slots per node**: 2 mapping entries (prev pointer + next pointer), plus the node's existence is implicit from having non-zero neighbors. The sentinel node (0) acts as head/tail anchor.
- **Total overhead**: 1 slot for size + 2 mapping slots per node.

#### Operations Supported

| Operation | Supported | Complexity |
|-----------|-----------|------------|
| Insert (head/tail) | Yes | O(1) |
| Insert (ordered) | Yes | O(n) - walks list to find position |
| Insert (after/before specific node) | Yes | O(1) |
| Remove | Yes | O(1) |
| Iterate (getNextNode/getPreviousNode) | Yes | O(1) per step |
| Lookup (nodeExists) | Yes | O(1) |
| Size | Yes | O(1) |

#### Key Characteristics

- Uses `uint256` as node identifiers (easily adaptable to bytes32 via casting).
- Sentinel node pattern: node 0 is the sentinel. `list[0][NEXT]` = head, `list[0][PREV]` = tail.
- Library operates on `List storage` pointer -- compatible with namespaced storage if the `List` struct is embedded in a namespaced storage struct.
- Supports both ordered (sorted) and unordered insertion.
- Does NOT support skip/filter during traversal natively (but trivially composable).
- No gas benchmarks published.
- Not formally audited, but widely used (Aragon, other DeFi protocols).
- **Best candidate for adaptation.**

#### Namespaced Storage Compatibility

The library uses `List storage self` pattern, meaning it accepts a storage pointer. This is directly compatible with the project's namespaced storage pattern:

```solidity
struct MyStorage {
    StructuredLinkedList.List subscriptions;
}

bytes32 constant SLOT = keccak256("reactive.subscriptions");

function myStorage() pure returns (MyStorage storage $) {
    bytes32 s = SLOT;
    assembly { $.slot := s }
}
// Usage: StructuredLinkedList.pushFront(myStorage().subscriptions, nodeId);
```

---

### 1.2 Modular-Network/ethereum-libraries (LinkedListLib)

- **Repository**: https://github.com/modular-network/ethereum-libraries
  - Subdirectory: `LinkedListLib/`
- **License**: MIT
- **Solidity version**: Originally ^0.4.x, updated forks exist for ^0.8.x but the main repo is largely unmaintained (last significant update 2018-2019).
- **Status**: Archived/unmaintained. The canonical successor is vittominacori/solidity-linked-list, which was forked from and improved upon this library.

#### Storage Layout

```solidity
struct LinkedList {
    mapping(uint256 => mapping(bool => uint256)) list;
}
```

- Same sentinel-based design as vittominacori's version (which descended from this).
- No `size` tracking -- must be maintained externally if needed.

#### Operations Supported

| Operation | Supported | Complexity |
|-----------|-----------|------------|
| Insert (before/after) | Yes | O(1) |
| Insert (sorted) | Yes | O(n) |
| Remove | Yes | O(1) |
| Iterate | Yes | O(1) per step |
| Size | No (manual tracking) | N/A |

#### Key Characteristics

- Historical significance as the original Solidity DLL library.
- Unmaintained -- would require manual porting to modern Solidity.
- No audits.
- **Not recommended due to unmaintained status.** Use vittominacori's fork instead.

---

### 1.3 HQ20/contracts (DoublyLinkedList)

- **Repository**: https://github.com/HQ20/contracts
  - Path: `contracts/lists/`
- **License**: Apache-2.0
- **Solidity version**: ^0.6.x (would require porting)
- **Status**: Educational/reference implementation, not actively maintained since 2021.

#### Storage Layout

```solidity
struct Object {
    uint256 id;
    uint256 next;
    uint256 prev;
    bytes data;
}

struct DLL {
    mapping(uint256 => Object) objects;
    uint256 head;
    uint256 tail;
    uint256 idCounter;
}
```

- **Slots per node**: 4+ slots (id, next, prev, plus dynamic bytes data).
- Significantly more expensive than mapping-based approaches.

#### Operations Supported

| Operation | Supported | Complexity |
|-----------|-----------|------------|
| Insert (head/tail) | Yes | O(1) |
| Insert (after/before) | Yes | O(1) |
| Remove | Yes | O(1) |
| Iterate | Yes | O(1) per step |
| Lookup | Yes | O(1) |

#### Key Characteristics

- Stores arbitrary `bytes` data per node -- most flexible data model.
- Auto-incrementing ID counter (not suitable for external bytes32 IDs without modification).
- Higher gas costs due to struct storage.
- Educational quality -- good for understanding the pattern, not for production.
- **Not recommended**: outdated Solidity, heavy storage, auto-increment IDs.

---

### 1.4 Uniswap v4 PoolManager (internal linked structures)

- **Repository**: https://github.com/Uniswap/v4-core (already a dependency of this project)
- **License**: BUSL-1.1 (Business Source License -- restrictive)
- **Relevant files**: No standalone linked list primitive exposed. Uniswap v4 uses tick bitmaps and mappings for ordered data, not linked lists.
- **Status**: Not applicable -- no DLL implementation.

---

### 1.5 solady (Vectorize / LibSort / etc.)

- **Repository**: https://github.com/Vectorized/solady
- **License**: MIT
- **Linked list primitives**: **None**. Solady focuses on gas-optimized math (FixedPointMathLib), auth (Ownable, OwnableRoles), ERC tokens, and utility functions. It provides `LibSort` for in-memory sorting and `EnumerableSetLib` for enumerable sets, but no linked list data structure.
- **EnumerableSetLib** is the closest primitive -- it provides O(1) add/remove/contains for address/bytes32/uint256 sets, but does NOT preserve insertion order and does NOT support ordered iteration or prev/next traversal.
- **Status**: Not applicable.

---

### 1.6 OpenZeppelin Contracts

- **Repository**: https://github.com/OpenZeppelin/openzeppelin-contracts
- **License**: MIT
- **Linked list primitives**: **Removed**. OpenZeppelin had `DoubleEndedQueue` (Deque) in earlier versions, which supports push/pop from both ends but NOT arbitrary removal or insertion at arbitrary positions. It was implemented as a contiguous array with head/tail indices, not a linked list.
- **EnumerableSet / EnumerableMap**: O(1) add/remove/contains, but no ordered iteration or prev/next semantics.
- **Status**: No DLL available. `DoubleEndedQueue` is not suitable (no O(1) arbitrary removal).

---

### 1.7 PRBMath / PRB Contracts

- **Repository**: https://github.com/PaulRBerg/prb-math
- **License**: MIT
- **Linked list primitives**: **None**. PRBMath is a fixed-point arithmetic library. Paul R. Berg's other repos (prb-contracts, prb-proxy) also do not contain linked list implementations.
- **Status**: Not applicable.

---

## 2. Comparative Analysis

### 2.1 Feature Matrix

| Feature | vittominacori | Modular-Network | HQ20 | OZ Deque |
|---------|--------------|-----------------|------|----------|
| Solidity >=0.8.26 | Yes | No (needs port) | No (needs port) | Partial (no DLL) |
| O(1) insert at ends | Yes | Yes | Yes | Yes (push only) |
| O(1) arbitrary remove | Yes | Yes | Yes | No |
| O(1) insert after node | Yes | Yes | Yes | No |
| Prev/next traversal | Yes | Yes | Yes | No |
| Size tracking | Yes | No | Yes (implicit) | Yes |
| Node data type | uint256 | uint256 | bytes | uint256 (index) |
| Sentinel pattern | Yes (node 0) | Yes (node 0) | No (head/tail ptrs) | N/A |
| Storage efficiency | 2 mapping slots/node | 2 mapping slots/node | 4+ struct slots/node | 1 slot/entry |
| Namespaced storage compat | Yes (storage ptr) | Yes (storage ptr) | Needs adaptation | N/A |
| Audited | No (widely used) | No | No | Yes (but no DLL) |
| Maintained | Yes | No | No | N/A |

### 2.2 Gas Cost Estimates (Theoretical)

These are approximate estimates based on EVM storage pricing (Cancun, post-EIP-1153):

| Operation | Sentinel-mapping DLL | Struct-based DLL |
|-----------|---------------------|------------------|
| Insert (cold, new node) | ~44,000 gas (2 SSTORE cold + 2 SSTORE warm for neighbor updates) | ~66,000+ gas (3-4 SSTORE cold for struct fields) |
| Insert (warm) | ~10,000 gas | ~15,000+ gas |
| Remove (warm) | ~10,000 gas (4 SSTORE warm: clear node + update neighbors) | ~15,000+ gas |
| Iterate (per step) | ~2,100 gas (1 SLOAD cold) or ~100 gas (warm) | ~4,200+ gas (2 SLOAD cold) |
| Size check | ~2,100 gas (1 SLOAD) | ~2,100 gas |

The sentinel-mapping approach (vittominacori/Modular-Network) is clearly more gas-efficient.

---

## 3. Requirements Analysis for reactive-hooks

### 3.1 Namespaced Storage Compatibility

The project uses the keccak256 slot isolation pattern extensively:

- `/home/jmsbpp/utils/reactive-hooks/src/modules/CallbackStorageMod.sol` (line 12): `keccak256("reactive.callback.storage")`
- `/home/jmsbpp/utils/reactive-hooks/src/modules/ReactVMMod.sol` (line 11): `keccak256("reactive.reactVM")`
- `/home/jmsbpp/utils/reactive-hooks/src/modules/ReactVmStorageMod.sol` (line 18): `keccak256("ThetaSwapReactive.vm.storage")`

All use the pattern:
```solidity
function storageAccessor() pure returns (StorageStruct storage $) {
    bytes32 slot = CONSTANT_SLOT;
    assembly ("memory-safe") { $.slot := slot }
}
```

Any DLL implementation must work as a field within such a namespaced struct. The vittominacori `List` struct (containing a `mapping` and a `uint256`) works correctly in this pattern because Solidity computes mapping storage locations relative to the struct's base slot.

### 3.2 O(1) Insert and Remove Without Reordering

Both vittominacori and Modular-Network satisfy this. Insert at head/tail and remove by node ID are O(1). The remaining nodes' order is preserved -- no reordering occurs.

### 3.3 Iteration with Skip (Pause Semantics)

No existing implementation provides built-in skip/filter during traversal. However, the sentinel-mapping pattern makes this trivial to compose:

```solidity
function iterateSkippingPaused(List storage self, mapping(uint256 => bool) storage paused) {
    (, uint256 node) = self.getNextNode(0); // start from head
    while (node != 0) {
        if (!paused[node]) {
            // process node
        }
        (, node) = self.getNextNode(node);
    }
}
```

This is a non-issue -- skip semantics belong in the application layer, not the data structure.

### 3.4 Generic Over Node Data Type (bytes32 IDs)

The vittominacori library uses `uint256` as node identifiers. Since `bytes32` and `uint256` are both 32-byte stack values with identical EVM representation, conversion is zero-cost:

```solidity
uint256(nodeId)  // bytes32 -> uint256
bytes32(nodeId)  // uint256 -> bytes32
```

A custom implementation could use `bytes32` natively to avoid the casts, but this is purely cosmetic.

### 3.5 Foundry Compatibility

All evaluated libraries are pure Solidity with no external dependencies, making them inherently Foundry-compatible. The project already uses Foundry with `solc_version = "0.8.26"` and `evm_version = "cancun"` (see `/home/jmsbpp/utils/reactive-hooks/foundry.toml`, lines 6-7).

---

## 4. Detailed Design Notes: Sentinel-Mapping Pattern

The sentinel-mapping pattern (shared by vittominacori and Modular-Network) deserves detailed explanation since it is the recommended foundation.

### 4.1 How It Works

- Node `0` is the **sentinel** -- it is never a real node. It serves as both the head anchor and tail anchor.
- `list[0][NEXT]` = the first real node (head).
- `list[0][PREV]` = the last real node (tail).
- `list[node][NEXT]` = the next node after `node`.
- `list[node][PREV]` = the previous node before `node`.
- A node exists if and only if `list[node][NEXT] != 0 || list[node][PREV] != 0` (or the node is the only node, in which case both point to sentinel 0 and the sentinel points back to it).

### 4.2 Storage Slot Computation

For a `mapping(uint256 => mapping(bool => uint256))` at storage slot `s`:

```
slot_of(list[nodeId][direction]) = keccak256(direction . keccak256(nodeId . s))
```

Where `.` denotes concatenation and `direction` is `0` (PREV) or `1` (NEXT). Each node's two pointers are at deterministic, collision-resistant slots. This is inherently compatible with namespaced storage since `s` is derived from the struct's base slot.

### 4.3 Sentinel Advantages

- No special-casing for empty list, single-element list, or boundary operations.
- Insert/remove are always the same 4-pointer-update algorithm.
- Head and tail are accessed uniformly through `list[0][NEXT]` and `list[0][PREV]`.

---

## 5. Recommendation

### Primary Recommendation: Write a Custom Implementation

**Rationale**: None of the existing implementations are a perfect fit. The gaps are small but important:

1. **Convention mismatch**: The project uses free functions with storage pointers (e.g., `function coverDebt(address self)` at `/home/jmsbpp/utils/reactive-hooks/src/libraries/DebtLib.sol`), not `library` + `using for` patterns. The vittominacori library uses `library StructuredLinkedList` with `using StructuredLinkedList for StructuredLinkedList.List`. While `using for` works, it diverges from the project's established convention of free functions operating on storage structs.

2. **Node type**: The project will store `bytes32` IDs. A custom implementation can use `bytes32` natively, avoiding `uint256` casts that obscure intent.

3. **Minimalism**: The project does not need sorted insertion, which accounts for a significant portion of the vittominacori codebase. A custom implementation can be smaller and more auditable.

4. **Pause-aware iteration helpers**: While skip logic belongs in the application layer, having purpose-built iteration helpers (e.g., `forEachActive`) in the library itself would reduce boilerplate across the codebase.

### Best Reference Implementation: vittominacori/solidity-linked-list

Use this as the structural reference for the custom implementation because:

- It is the most mature and widely-used Solidity DLL.
- The sentinel-mapping pattern is proven and gas-efficient.
- The storage pointer pattern (`List storage self`) is directly compatible with namespaced storage.
- It handles all edge cases (empty list, single node, remove head/tail).

### Proposed Custom Implementation Skeleton

```
src/libraries/DoublyLinkedListLib.sol
```

The implementation should:

1. Use a struct with `mapping(bytes32 => mapping(bool => bytes32))` and `uint256 size`.
2. Use `bytes32(0)` as the sentinel node.
3. Expose free functions: `pushFront`, `pushBack`, `insertAfter`, `insertBefore`, `remove`, `next`, `prev`, `head`, `tail`, `size`, `contains`.
4. NOT include sorted insertion (not needed).
5. Accept `StorageStruct storage` parameters to work with namespaced storage.
6. Include NatSpec documentation referencing vittominacori as the design origin.

### Estimated Implementation Effort

- Core DLL library: ~80-120 lines of Solidity
- Foundry test suite: ~150-200 lines
- Total: 1-2 hours of implementation + testing

### Alternative Considered and Rejected: Vendoring vittominacori

Vendoring the library directly (via `forge install vittominacori/solidity-linked-list`) is viable but suboptimal:

- Adds a dependency for ~200 lines of code, half of which (sorted insertion) is unused.
- Forces adoption of the `library` + `using for` pattern, inconsistent with the rest of the codebase.
- Requires wrapping in free functions anyway to match conventions, resulting in double indirection.

---

## 6. Audit and Security Considerations

### No Existing Implementation Has Been Formally Audited

This is an important caveat. The vittominacori library has been used in production protocols (including Aragon and others), which provides some battle-testing, but it has never undergone a formal security audit.

### Key Attack Surfaces for DLL in This Context

1. **Ghost nodes**: Attempting to remove a node that does not exist. The vittominacori library handles this by checking `nodeExists` before removal. A custom implementation must do the same.

2. **Re-insertion**: Inserting a node ID that already exists. This must either revert or be a no-op. The vittominacori library reverts.

3. **Sentinel corruption**: Operations that would modify the sentinel node (ID 0 or bytes32(0)). Must be prevented with explicit checks.

4. **Iterator invalidation**: Removing a node during iteration. The sentinel pattern handles this gracefully -- if you remove the current node, you must have already cached the next pointer. This is a caller responsibility.

5. **Storage collision**: Not a risk with the mapping-based approach, as Solidity's storage layout guarantees collision resistance for mappings.

### Recommendation for Testing

Write Foundry fuzz tests covering:
- Insert/remove sequences with randomized node IDs
- Invariant: size always equals the number of reachable nodes from head
- Invariant: forward traversal and reverse traversal visit the same nodes in opposite order
- Edge cases: empty list operations, single-node list, remove head, remove tail

---

## 7. Summary Table

| Criterion | vittominacori | Custom (recommended) |
|-----------|--------------|---------------------|
| Solidity >=0.8.26 | Yes | Yes |
| Namespaced storage | Yes (via storage ptr) | Yes (native) |
| O(1) insert/remove | Yes | Yes |
| Iteration with skip | Composable | Built-in helpers |
| bytes32 node IDs | Via cast | Native |
| Code convention match | Library pattern | Free function pattern |
| Sorted insertion | Yes (unused) | Omitted |
| Maintenance burden | External dependency | Internal (~100 lines) |
| Foundry compatible | Yes | Yes |

---

## 8. Next Steps

1. Create `src/libraries/DoublyLinkedListLib.sol` using the sentinel-mapping pattern from vittominacori as reference.
2. Use `bytes32` as the native node type.
3. Implement as free functions operating on a storage struct, matching the project's convention seen in `SubscriptionLib.sol`, `DebtLib.sol`, and the storage modules.
4. Write Foundry fuzz tests with the invariants described in Section 6.
5. Integrate with the subscription/callback dispatch system where ordered iteration over active subscriptions is needed.
