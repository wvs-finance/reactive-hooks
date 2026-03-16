# DoublyLinkedListLib — Design Specification

## Overview

A generic, gas-efficient doubly-linked list for Solidity `^0.8.26`, built on the sentinel-mapping pattern from vittominacori/solidity-linked-list. Designed as a standalone storage primitive for the reactive-hooks project, with immediate use in the Event Dispatch Table (EDT) for F7 fan-out dispatch.

## Motivation

The EDT requires an ordered container of `bytes32` binding IDs per origin, supporting O(1) insert/remove and forward/reverse iteration with caller-side pause/skip. No existing Solidity library satisfies all project constraints: `bytes32` native nodes, free-function convention, namespaced storage compatibility, and no unused features (sorted insertion). A custom ~100-120 line implementation fills this gap.

## Storage Layout

```solidity
bytes32 constant SENTINEL = bytes32(0);
bool constant PREV = false;
bool constant NEXT = true;

struct DLL {
    uint256 size;
    mapping(bytes32 => mapping(bool => bytes32)) nodes;
}
```

### Co-location Rationale

The `DLL` struct, constants, errors, and free functions are all defined in a single file (`DoublyLinkedListLib.sol`). The project normally separates types into `src/types/`, but the DLL is a self-contained primitive with no external consumers that need the type without the functions. Co-location avoids a circular import and keeps the primitive atomic.

### Sentinel Pattern

- `nodes[SENTINEL][NEXT]` = head (first real node)
- `nodes[SENTINEL][PREV]` = tail (last real node)
- `nodes[id][NEXT]` = successor of `id`
- `nodes[id][PREV]` = predecessor of `id`
- `bytes32(0)` is reserved as the sentinel and can never be a valid node ID

### Namespaced Storage Compatibility

The `DLL` struct is embedded in keccak256-isolated storage structs:

```solidity
struct EDTStorage {
    DLL callbackList;
}

bytes32 constant SLOT = keccak256("reactive.edt.storage");

function edtStorage() pure returns (EDTStorage storage $) {
    bytes32 s = SLOT;
    assembly ("memory-safe") { $.slot := s }
}
```

Mapping storage slots are computed relative to the struct's base slot, so namespaced isolation is preserved.

### Storage Cost

- 1 slot for `size`
- 2 mapping slots per node (prev pointer + next pointer)
- ~44,000 gas cold insert, ~10,000 gas warm insert
- ~2,100 gas per iteration step (cold SLOAD)

## API Surface

All free functions taking `DLL storage self` as first parameter. Every mutation reverts on invalid input (strict, not idempotent).

### Mutations

| Function | Signature | Reverts when |
|----------|-----------|--------------|
| `pushFront` | `(DLL storage, bytes32 id)` | `id` is sentinel or already exists |
| `pushBack` | `(DLL storage, bytes32 id)` | `id` is sentinel or already exists |
| `insertAfter` | `(DLL storage, bytes32 anchor, bytes32 id)` | `anchor` doesn't exist, or `id` is sentinel/already exists |
| `insertBefore` | `(DLL storage, bytes32 anchor, bytes32 id)` | `anchor` doesn't exist, or `id` is sentinel/already exists |
| `remove` | `(DLL storage, bytes32 id)` | `id` is sentinel or doesn't exist |

### Queries

| Function | Signature | Returns |
|----------|-----------|---------|
| `next` | `(DLL storage, bytes32 id) → bytes32` | Next node, or `SENTINEL` if tail. Reverts if `id` does not exist. |
| `prev` | `(DLL storage, bytes32 id) → bytes32` | Prev node, or `SENTINEL` if head. Reverts if `id` does not exist. |
| `head` | `(DLL storage) → bytes32` | First node, or `SENTINEL` if empty |
| `tail` | `(DLL storage) → bytes32` | Last node, or `SENTINEL` if empty |
| `size` | `(DLL storage) → uint256` | Node count |
| `contains` | `(DLL storage, bytes32 id) → bool` | Whether node exists |
| `isEmpty` | `(DLL storage) → bool` | `size == 0` |

### Iteration Pattern (Caller-Side)

```solidity
bytes32 node = self.head();
while (node != SENTINEL) {
    // process node
    node = self.next(node);
}
```

The DLL has no iteration helpers. The research reference (Section 5) suggested built-in `forEachActive`-style helpers, but this was rejected: pause/skip semantics are EDT-specific and would couple the generic primitive to application logic. Pause/skip belongs in the EDT dispatch layer.

## Core Algorithm

The sentinel pattern means every mutation is the same 4-pointer update. No special cases for empty list, single node, or boundary operations.

### Insert (Internal Helper)

All public insert functions resolve to a single internal helper:

```
_insert(self, prevNode, id, nextNode)

1. self.nodes[id][PREV] = prevNode
2. self.nodes[id][NEXT] = nextNode
3. self.nodes[prevNode][NEXT] = id
4. self.nodes[nextNode][PREV] = id
5. self.size++
```

Public functions resolve anchors:
- `pushFront(id)` → `_insert(SENTINEL, id, nodes[SENTINEL][NEXT])`
- `pushBack(id)` → `_insert(nodes[SENTINEL][PREV], id, SENTINEL)`
- `insertAfter(anchor, id)` → `_insert(anchor, id, nodes[anchor][NEXT])`
- `insertBefore(anchor, id)` → `_insert(nodes[anchor][PREV], id, anchor)`

### Remove

```
remove(self, id)

1. prevNode = self.nodes[id][PREV]
2. nextNode = self.nodes[id][NEXT]
3. self.nodes[prevNode][NEXT] = nextNode
4. self.nodes[nextNode][PREV] = prevNode
5. self.nodes[id][PREV] = SENTINEL   // clear (gas refund)
6. self.nodes[id][NEXT] = SENTINEL   // clear (gas refund)
7. self.size--
```

### Contains

```
contains(self, id)
  return id != SENTINEL && (
    self.nodes[id][NEXT] != SENTINEL ||
    self.nodes[id][PREV] != SENTINEL ||
    self.nodes[SENTINEL][NEXT] == id   // single-node case
  )
```

### Errors

```solidity
error NodeAlreadyExists(bytes32 id);
error NodeDoesNotExist(bytes32 id);
error InvalidNode();  // sentinel passed as id
```

## Validation Rules

Every mutation validates before modifying state:

- **Sentinel guard**: `id == SENTINEL` → revert `InvalidNode()`
- **Existence guard (insert)**: `contains(id)` → revert `NodeAlreadyExists(id)`
- **Existence guard (remove)**: `!contains(id)` → revert `NodeDoesNotExist(id)`
- **Anchor guard (insertAfter/Before)**: `!contains(anchor)` → revert `NodeDoesNotExist(anchor)`
- **Anchor sentinel guard**: `anchor == SENTINEL` in `insertAfter`/`insertBefore` → revert `InvalidNode()`. Use `pushFront`/`pushBack` for boundary insertion instead.
- **Query guard (next/prev)**: `!contains(id)` → revert `NodeDoesNotExist(id)`. This prevents silent `SENTINEL` returns for non-existent nodes being confused with legitimate tail/head results.

## Testing Strategy

### File

`test/libraries/DoublyLinkedListLib.t.sol`

### Test Harness

A thin contract wrapping free functions for external access, enabling Foundry's invariant testing engine.

### Unit Tests

Deterministic tests covering every function and revert path:
- Insert into empty list (pushFront, pushBack)
- Insert into non-empty list (all four insert functions)
- Remove head, tail, middle, only node
- Revert: duplicate insert, remove non-existent, sentinel as argument
- Query correctness: contains, size, isEmpty, head, tail after each mutation

### Fuzz Tests

- `testFuzz_insertRemoveSequence(bytes32[] ids)` — insert all, verify size, remove all, verify empty
- `testFuzz_orderPreservation(bytes32[] ids)` — pushBack all, iterate forward, assert same order

### Invariant Tests

- **INV-1**: `size` equals number of nodes reachable from `head()` walking `next()`
- **INV-2**: Forward traversal and reverse traversal visit the same nodes in opposite order
- **INV-3**: `contains(SENTINEL)` is always `false`
- **INV-4**: After `remove(id)`, `contains(id)` is `false` and `size` decremented by 1

## File Layout

```
src/libraries/DoublyLinkedListLib.sol    — struct DLL + free functions (~100-120 lines)
test/libraries/DoublyLinkedListLib.t.sol — unit + fuzz + invariant tests (~250-300 lines)
```

## Dependencies

None. Pure Solidity, no external libraries.

## Integration Point

The DLL is a standalone primitive. EDT integration happens when F7 (Fan-Out Dispatch) is implemented — `EDTStorage` will embed a `DLL` field per origin, and dispatch iterates the list calling `next()` while skipping paused bindings.

## Design References

- vittominacori/solidity-linked-list (MIT) — sentinel-mapping pattern, structural reference
- refs/doubly-linked-list-implementations.md — research report evaluating 6 implementations
- refs/edt-flows.md — F7 (Fan-Out Dispatch) defines the EDT use case
