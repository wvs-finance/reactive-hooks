# DoublyLinkedListLib Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a generic, gas-efficient doubly-linked list library using the sentinel-mapping pattern with `bytes32` nodes and free functions.

**Architecture:** Single-file library (`DoublyLinkedListLib.sol`) with struct, constants, errors, 12 public free functions, and 3 internal helpers (`_insert`, `_validateInsert`, `_validateAnchor`). Test harness contract wraps free functions for Foundry's invariant engine. TDD throughout — every function gets a failing test before implementation.

**Tech Stack:** Solidity ^0.8.26, Foundry (forge), Cancun EVM

**Spec:** `docs/superpowers/specs/2026-03-16-doubly-linked-list-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `src/libraries/DoublyLinkedListLib.sol` | DLL struct, SENTINEL/PREV/NEXT constants, 3 errors, 12 public free functions, 3 internal helpers (`_insert`, `_validateInsert`, `_validateAnchor`) |
| `test/libraries/DoublyLinkedListLib.t.sol` | Test harness contract + unit tests + fuzz tests + invariant tests |

No existing files are modified. Both files are created from scratch.

---

## Chunk 1: Foundation — Struct, Constants, Errors, Contains, and pushBack

### Task 1: Scaffold library with struct, constants, errors, and contains

**Files:**
- Create: `src/libraries/DoublyLinkedListLib.sol`
- Create: `test/libraries/DoublyLinkedListLib.t.sol`

- [ ] **Step 1: Write failing test for `contains` on empty list**

```solidity
// test/libraries/DoublyLinkedListLib.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DLL, SENTINEL, PREV, NEXT, contains, isEmpty, size, head, tail} from "../../src/libraries/DoublyLinkedListLib.sol";

contract DLLHarness {
    DLL internal list;

    function contains_(bytes32 id) external view returns (bool) { return contains(list, id); }
    function isEmpty_() external view returns (bool) { return isEmpty(list); }
    function size_() external view returns (uint256) { return size(list); }
    function head_() external view returns (bytes32) { return head(list); }
    function tail_() external view returns (bytes32) { return tail(list); }
}

contract DoublyLinkedListLibTest is Test {
    DLLHarness internal harness;

    function setUp() public {
        harness = new DLLHarness();
    }

    function test_emptyList_containsReturnsFalse() public view {
        assertFalse(harness.contains_(bytes32(uint256(1))));
    }

    function test_emptyList_containsSentinelReturnsFalse() public view {
        assertFalse(harness.contains_(SENTINEL));
    }

    function test_emptyList_isEmptyReturnsTrue() public view {
        assertTrue(harness.isEmpty_());
    }

    function test_emptyList_sizeIsZero() public view {
        assertEq(harness.size_(), 0);
    }

    function test_emptyList_headIsSentinel() public view {
        assertEq(harness.head_(), SENTINEL);
    }

    function test_emptyList_tailIsSentinel() public view {
        assertEq(harness.tail_(), SENTINEL);
    }
}
```

- [ ] **Step 2: Run test to verify it fails (compilation error — library doesn't exist)**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: Compilation error — `DoublyLinkedListLib.sol` not found

- [ ] **Step 3: Write minimal library — struct, constants, errors, query functions**

```solidity
// src/libraries/DoublyLinkedListLib.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @dev Sentinel node — represents "no node" / list boundary. bytes32(0) is never a valid node ID.
bytes32 constant SENTINEL = bytes32(0);

/// @dev Direction constants for the nested mapping.
bool constant PREV = false;
bool constant NEXT = true;

/// @dev A doubly-linked list of bytes32 node IDs using the sentinel-mapping pattern.
/// @dev Design reference: vittominacori/solidity-linked-list (MIT).
struct DLL {
    uint256 size;
    mapping(bytes32 => mapping(bool => bytes32)) nodes;
}

error NodeAlreadyExists(bytes32 id);
error NodeDoesNotExist(bytes32 id);
error InvalidNode();

/// @dev Returns true if `id` is a member of the list.
function contains(DLL storage self, bytes32 id) view returns (bool) {
    if (id == SENTINEL) return false;
    return self.nodes[id][NEXT] != SENTINEL
        || self.nodes[id][PREV] != SENTINEL
        || self.nodes[SENTINEL][NEXT] == id;
}

/// @dev Returns the number of nodes in the list.
function size(DLL storage self) view returns (uint256) {
    return self.size;
}

/// @dev Returns true if the list has no nodes.
function isEmpty(DLL storage self) view returns (bool) {
    return self.size == 0;
}

/// @dev Returns the first node, or SENTINEL if the list is empty.
function head(DLL storage self) view returns (bytes32) {
    return self.nodes[SENTINEL][NEXT];
}

/// @dev Returns the last node, or SENTINEL if the list is empty.
function tail(DLL storage self) view returns (bytes32) {
    return self.nodes[SENTINEL][PREV];
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: All 6 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/libraries/DoublyLinkedListLib.sol test/libraries/DoublyLinkedListLib.t.sol
git commit -m "feat(dll): scaffold struct, constants, errors, and query functions"
```

---

### Task 2: Implement pushBack and its tests

**Files:**
- Modify: `src/libraries/DoublyLinkedListLib.sol`
- Modify: `test/libraries/DoublyLinkedListLib.t.sol`

- [ ] **Step 1: Write failing tests for pushBack**

Add to `DLLHarness`:
```solidity
function pushBack_(bytes32 id) external { pushBack(list, id); }
```

Add to `DoublyLinkedListLibTest`:
```solidity
function test_pushBack_singleNode() public {
    bytes32 A = bytes32(uint256(1));
    harness.pushBack_(A);
    assertTrue(harness.contains_(A));
    assertEq(harness.size_(), 1);
    assertEq(harness.head_(), A);
    assertEq(harness.tail_(), A);
}

function test_pushBack_twoNodes_orderPreserved() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    harness.pushBack_(A);
    harness.pushBack_(B);
    assertEq(harness.head_(), A);
    assertEq(harness.tail_(), B);
    assertEq(harness.size_(), 2);
}

function test_pushBack_revertOnSentinel() public {
    vm.expectRevert(InvalidNode.selector);
    harness.pushBack_(SENTINEL);
}

function test_pushBack_revertOnDuplicate() public {
    bytes32 A = bytes32(uint256(1));
    harness.pushBack_(A);
    vm.expectRevert(abi.encodeWithSelector(NodeAlreadyExists.selector, A));
    harness.pushBack_(A);
}
```

Update import to include `pushBack, InvalidNode, NodeAlreadyExists`.

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: Compilation error — `pushBack` not found

- [ ] **Step 3: Implement _insert helper and pushBack**

Add to `DoublyLinkedListLib.sol`:
```solidity
/// @dev Insert `id` between `prevNode` and `nextNode`. Internal — no validation.
function _insert(DLL storage self, bytes32 prevNode, bytes32 id, bytes32 nextNode) {
    self.nodes[id][PREV] = prevNode;
    self.nodes[id][NEXT] = nextNode;
    self.nodes[prevNode][NEXT] = id;
    self.nodes[nextNode][PREV] = id;
    self.size++;
}

/// @dev Validates `id` is not sentinel and does not already exist. Used by all insert functions.
function _validateInsert(DLL storage self, bytes32 id) view {
    if (id == SENTINEL) revert InvalidNode();
    if (contains(self, id)) revert NodeAlreadyExists(id);
}

/// @dev Append `id` to the end of the list.
function pushBack(DLL storage self, bytes32 id) {
    _validateInsert(self, id);
    _insert(self, self.nodes[SENTINEL][PREV], id, SENTINEL);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: All 10 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/libraries/DoublyLinkedListLib.sol test/libraries/DoublyLinkedListLib.t.sol
git commit -m "feat(dll): implement _insert helper and pushBack with validation"
```

---

### Task 3: Implement pushFront and its tests

**Files:**
- Modify: `src/libraries/DoublyLinkedListLib.sol`
- Modify: `test/libraries/DoublyLinkedListLib.t.sol`

- [ ] **Step 1: Write failing tests for pushFront**

Add to `DLLHarness`:
```solidity
function pushFront_(bytes32 id) external { pushFront(list, id); }
```

Add to `DoublyLinkedListLibTest`:
```solidity
function test_pushFront_singleNode() public {
    bytes32 A = bytes32(uint256(1));
    harness.pushFront_(A);
    assertTrue(harness.contains_(A));
    assertEq(harness.size_(), 1);
    assertEq(harness.head_(), A);
    assertEq(harness.tail_(), A);
}

function test_pushFront_twoNodes_orderPreserved() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    harness.pushFront_(A);
    harness.pushFront_(B);
    assertEq(harness.head_(), B);  // B was pushed to front
    assertEq(harness.tail_(), A);
    assertEq(harness.size_(), 2);
}

function test_pushFront_revertOnSentinel() public {
    vm.expectRevert(InvalidNode.selector);
    harness.pushFront_(SENTINEL);
}

function test_pushFront_revertOnDuplicate() public {
    bytes32 A = bytes32(uint256(1));
    harness.pushFront_(A);
    vm.expectRevert(abi.encodeWithSelector(NodeAlreadyExists.selector, A));
    harness.pushFront_(A);
}
```

Update import to include `pushFront`.

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: Compilation error — `pushFront` not found

- [ ] **Step 3: Implement pushFront**

Add to `DoublyLinkedListLib.sol`:
```solidity
/// @dev Prepend `id` to the front of the list.
function pushFront(DLL storage self, bytes32 id) {
    _validateInsert(self, id);
    _insert(self, SENTINEL, id, self.nodes[SENTINEL][NEXT]);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: All 14 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/libraries/DoublyLinkedListLib.sol test/libraries/DoublyLinkedListLib.t.sol
git commit -m "feat(dll): implement pushFront"
```

---

## Chunk 2: next/prev, remove, insertAfter/Before

### Task 4: Implement next and prev with tests

**Files:**
- Modify: `src/libraries/DoublyLinkedListLib.sol`
- Modify: `test/libraries/DoublyLinkedListLib.t.sol`

- [ ] **Step 1: Write failing tests for next and prev**

Add to `DLLHarness`:
```solidity
function next_(bytes32 id) external view returns (bytes32) { return next(list, id); }
function prev_(bytes32 id) external view returns (bytes32) { return prev(list, id); }
```

Add to `DoublyLinkedListLibTest`:
```solidity
function test_next_singleNode_returnsSentinel() public {
    bytes32 A = bytes32(uint256(1));
    harness.pushBack_(A);
    assertEq(harness.next_(A), SENTINEL);
}

function test_prev_singleNode_returnsSentinel() public {
    bytes32 A = bytes32(uint256(1));
    harness.pushBack_(A);
    assertEq(harness.prev_(A), SENTINEL);
}

function test_next_twoNodes_traversal() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    harness.pushBack_(A);
    harness.pushBack_(B);
    assertEq(harness.next_(A), B);
    assertEq(harness.next_(B), SENTINEL);
}

function test_prev_twoNodes_traversal() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    harness.pushBack_(A);
    harness.pushBack_(B);
    assertEq(harness.prev_(B), A);
    assertEq(harness.prev_(A), SENTINEL);
}

function test_next_revertOnNonExistent() public {
    vm.expectRevert(abi.encodeWithSelector(NodeDoesNotExist.selector, bytes32(uint256(99))));
    harness.next_(bytes32(uint256(99)));
}

function test_prev_revertOnNonExistent() public {
    vm.expectRevert(abi.encodeWithSelector(NodeDoesNotExist.selector, bytes32(uint256(99))));
    harness.prev_(bytes32(uint256(99)));
}
```

Update import to include `next, prev, NodeDoesNotExist`.

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: Compilation error — `next`/`prev` not found

- [ ] **Step 3: Implement next and prev**

Add to `DoublyLinkedListLib.sol`:
```solidity
/// @dev Returns the successor of `id`, or SENTINEL if `id` is the tail. Reverts if `id` is not in the list.
function next(DLL storage self, bytes32 id) view returns (bytes32) {
    if (!contains(self, id)) revert NodeDoesNotExist(id);
    return self.nodes[id][NEXT];
}

/// @dev Returns the predecessor of `id`, or SENTINEL if `id` is the head. Reverts if `id` is not in the list.
function prev(DLL storage self, bytes32 id) view returns (bytes32) {
    if (!contains(self, id)) revert NodeDoesNotExist(id);
    return self.nodes[id][PREV];
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: All 20 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/libraries/DoublyLinkedListLib.sol test/libraries/DoublyLinkedListLib.t.sol
git commit -m "feat(dll): implement next and prev with existence guards"
```

---

### Task 5: Implement remove with tests

**Files:**
- Modify: `src/libraries/DoublyLinkedListLib.sol`
- Modify: `test/libraries/DoublyLinkedListLib.t.sol`

- [ ] **Step 1: Write failing tests for remove**

Add to `DLLHarness`:
```solidity
function remove_(bytes32 id) external { remove(list, id); }
```

Add to `DoublyLinkedListLibTest`:
```solidity
function test_remove_onlyNode() public {
    bytes32 A = bytes32(uint256(1));
    harness.pushBack_(A);
    harness.remove_(A);
    assertFalse(harness.contains_(A));
    assertEq(harness.size_(), 0);
    assertTrue(harness.isEmpty_());
    assertEq(harness.head_(), SENTINEL);
    assertEq(harness.tail_(), SENTINEL);
}

function test_remove_head() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    bytes32 C = bytes32(uint256(3));
    harness.pushBack_(A);
    harness.pushBack_(B);
    harness.pushBack_(C);
    harness.remove_(A);
    assertEq(harness.head_(), B);
    assertEq(harness.tail_(), C);
    assertEq(harness.size_(), 2);
    assertFalse(harness.contains_(A));
}

function test_remove_tail() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    bytes32 C = bytes32(uint256(3));
    harness.pushBack_(A);
    harness.pushBack_(B);
    harness.pushBack_(C);
    harness.remove_(C);
    assertEq(harness.head_(), A);
    assertEq(harness.tail_(), B);
    assertEq(harness.size_(), 2);
}

function test_remove_middle() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    bytes32 C = bytes32(uint256(3));
    harness.pushBack_(A);
    harness.pushBack_(B);
    harness.pushBack_(C);
    harness.remove_(B);
    assertEq(harness.next_(A), C);
    assertEq(harness.prev_(C), A);
    assertEq(harness.size_(), 2);
}

function test_remove_revertOnSentinel() public {
    vm.expectRevert(InvalidNode.selector);
    harness.remove_(SENTINEL);
}

function test_remove_revertOnNonExistent() public {
    vm.expectRevert(abi.encodeWithSelector(NodeDoesNotExist.selector, bytes32(uint256(99))));
    harness.remove_(bytes32(uint256(99)));
}
```

Update import to include `remove`.

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: Compilation error — `remove` not found

- [ ] **Step 3: Implement remove**

Add to `DoublyLinkedListLib.sol`:
```solidity
/// @dev Remove `id` from the list. Reverts if `id` is sentinel or not in the list.
function remove(DLL storage self, bytes32 id) {
    if (id == SENTINEL) revert InvalidNode();
    if (!contains(self, id)) revert NodeDoesNotExist(id);
    bytes32 prevNode = self.nodes[id][PREV];
    bytes32 nextNode = self.nodes[id][NEXT];
    self.nodes[prevNode][NEXT] = nextNode;
    self.nodes[nextNode][PREV] = prevNode;
    self.nodes[id][PREV] = SENTINEL;
    self.nodes[id][NEXT] = SENTINEL;
    self.size--;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: All 26 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/libraries/DoublyLinkedListLib.sol test/libraries/DoublyLinkedListLib.t.sol
git commit -m "feat(dll): implement remove with validation and pointer cleanup"
```

---

### Task 6: Implement insertAfter and insertBefore with tests

**Files:**
- Modify: `src/libraries/DoublyLinkedListLib.sol`
- Modify: `test/libraries/DoublyLinkedListLib.t.sol`

- [ ] **Step 1: Write failing tests for insertAfter and insertBefore**

Add to `DLLHarness`:
```solidity
function insertAfter_(bytes32 anchor, bytes32 id) external { insertAfter(list, anchor, id); }
function insertBefore_(bytes32 anchor, bytes32 id) external { insertBefore(list, anchor, id); }
```

Add to `DoublyLinkedListLibTest`:
```solidity
function test_insertAfter_middle() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    bytes32 C = bytes32(uint256(3));
    harness.pushBack_(A);
    harness.pushBack_(C);
    harness.insertAfter_(A, B);  // A -> B -> C
    assertEq(harness.next_(A), B);
    assertEq(harness.next_(B), C);
    assertEq(harness.prev_(C), B);
    assertEq(harness.size_(), 3);
}

function test_insertAfter_tail() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    harness.pushBack_(A);
    harness.insertAfter_(A, B);  // A -> B
    assertEq(harness.tail_(), B);
    assertEq(harness.next_(A), B);
    assertEq(harness.next_(B), SENTINEL);
}

function test_insertBefore_middle() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    bytes32 C = bytes32(uint256(3));
    harness.pushBack_(A);
    harness.pushBack_(C);
    harness.insertBefore_(C, B);  // A -> B -> C
    assertEq(harness.next_(A), B);
    assertEq(harness.next_(B), C);
    assertEq(harness.prev_(B), A);
    assertEq(harness.size_(), 3);
}

function test_insertBefore_head() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    harness.pushBack_(A);
    harness.insertBefore_(A, B);  // B -> A
    assertEq(harness.head_(), B);
    assertEq(harness.prev_(A), B);
    assertEq(harness.prev_(B), SENTINEL);
}

function test_insertAfter_revertOnSentinelAnchor() public {
    vm.expectRevert(InvalidNode.selector);
    harness.insertAfter_(SENTINEL, bytes32(uint256(1)));
}

function test_insertBefore_revertOnSentinelAnchor() public {
    vm.expectRevert(InvalidNode.selector);
    harness.insertBefore_(SENTINEL, bytes32(uint256(1)));
}

function test_insertAfter_revertOnNonExistentAnchor() public {
    vm.expectRevert(abi.encodeWithSelector(NodeDoesNotExist.selector, bytes32(uint256(99))));
    harness.insertAfter_(bytes32(uint256(99)), bytes32(uint256(1)));
}

function test_insertAfter_revertOnDuplicateId() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    harness.pushBack_(A);
    harness.pushBack_(B);
    vm.expectRevert(abi.encodeWithSelector(NodeAlreadyExists.selector, A));
    harness.insertAfter_(B, A);
}

function test_insertAfter_revertOnSentinelId() public {
    bytes32 A = bytes32(uint256(1));
    harness.pushBack_(A);
    vm.expectRevert(InvalidNode.selector);
    harness.insertAfter_(A, SENTINEL);
}

function test_insertBefore_revertOnNonExistentAnchor() public {
    vm.expectRevert(abi.encodeWithSelector(NodeDoesNotExist.selector, bytes32(uint256(99))));
    harness.insertBefore_(bytes32(uint256(99)), bytes32(uint256(1)));
}

function test_insertBefore_revertOnDuplicateId() public {
    bytes32 A = bytes32(uint256(1));
    bytes32 B = bytes32(uint256(2));
    harness.pushBack_(A);
    harness.pushBack_(B);
    vm.expectRevert(abi.encodeWithSelector(NodeAlreadyExists.selector, A));
    harness.insertBefore_(B, A);
}

function test_insertBefore_revertOnSentinelId() public {
    bytes32 A = bytes32(uint256(1));
    harness.pushBack_(A);
    vm.expectRevert(InvalidNode.selector);
    harness.insertBefore_(A, SENTINEL);
}
```

Update import to include `insertAfter, insertBefore`.

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: Compilation error — `insertAfter`/`insertBefore` not found

- [ ] **Step 3: Implement insertAfter and insertBefore**

Add to `DoublyLinkedListLib.sol`:
```solidity
/// @dev Validates anchor for insertAfter/insertBefore. Anchor must not be SENTINEL and must exist.
function _validateAnchor(DLL storage self, bytes32 anchor) view {
    if (anchor == SENTINEL) revert InvalidNode();
    if (!contains(self, anchor)) revert NodeDoesNotExist(anchor);
}

/// @dev Insert `id` immediately after `anchor`.
function insertAfter(DLL storage self, bytes32 anchor, bytes32 id) {
    _validateAnchor(self, anchor);
    _validateInsert(self, id);
    _insert(self, anchor, id, self.nodes[anchor][NEXT]);
}

/// @dev Insert `id` immediately before `anchor`.
function insertBefore(DLL storage self, bytes32 anchor, bytes32 id) {
    _validateAnchor(self, anchor);
    _validateInsert(self, id);
    _insert(self, self.nodes[anchor][PREV], id, anchor);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `forge test --match-contract DoublyLinkedListLibTest -v`
Expected: All 38 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/libraries/DoublyLinkedListLib.sol test/libraries/DoublyLinkedListLib.t.sol
git commit -m "feat(dll): implement insertAfter and insertBefore with anchor validation"
```

---

## Chunk 3: Fuzz and Invariant Tests

### Task 7: Fuzz tests

**Files:**
- Modify: `test/libraries/DoublyLinkedListLib.t.sol`

- [ ] **Step 1: Write fuzz test for insert/remove round-trip**

Add to `DoublyLinkedListLibTest`:
```solidity
function testFuzz_insertRemoveSequence(bytes32[] calldata ids) public {
    // Deduplicate and filter sentinel
    uint256 count;
    for (uint256 i; i < ids.length && i < 64; i++) {
        if (ids[i] == SENTINEL) continue;
        if (harness.contains_(ids[i])) continue;
        harness.pushBack_(ids[i]);
        count++;
    }
    assertEq(harness.size_(), count);

    // Remove all by walking from head
    bytes32 node = harness.head_();
    while (node != SENTINEL) {
        bytes32 nxt = harness.next_(node);
        harness.remove_(node);
        node = nxt;
    }
    assertEq(harness.size_(), 0);
    assertTrue(harness.isEmpty_());
}

function testFuzz_orderPreservation(bytes32[] calldata ids) public {
    // Insert unique non-sentinel IDs via pushBack, track insertion order
    bytes32[] memory inserted = new bytes32[](ids.length < 64 ? ids.length : 64);
    uint256 count;
    for (uint256 i; i < ids.length && i < 64; i++) {
        if (ids[i] == SENTINEL) continue;
        if (harness.contains_(ids[i])) continue;
        harness.pushBack_(ids[i]);
        inserted[count] = ids[i];
        count++;
    }

    // Walk forward and verify order matches insertion order
    bytes32 node = harness.head_();
    for (uint256 i; i < count; i++) {
        assertEq(node, inserted[i]);
        node = harness.next_(node);
    }
    assertEq(node, SENTINEL);  // past tail
}
```

- [ ] **Step 2: Run fuzz tests**

Run: `forge test --match-test testFuzz -v`
Expected: PASS (256 default fuzz runs each)

- [ ] **Step 3: Commit**

```bash
git add test/libraries/DoublyLinkedListLib.t.sol
git commit -m "test(dll): add fuzz tests for insert/remove round-trip and order preservation"
```

---

### Task 8: Invariant tests

**Files:**
- Modify: `test/libraries/DoublyLinkedListLib.t.sol`

- [ ] **Step 1: Add mutation handlers to harness for invariant testing**

Add to `DLLHarness`:
```solidity
/// @dev Bounded random insert/remove for invariant testing.
function pushBack_bounded(uint256 rawId) external {
    bytes32 id = bytes32(rawId % 256 + 1);  // 1..256, never sentinel
    if (contains(list, id)) return;  // skip if exists (invariant engine calls randomly)
    pushBack(list, id);
}

function remove_bounded(uint256 rawId) external {
    bytes32 id = bytes32(rawId % 256 + 1);
    if (!contains(list, id)) return;  // skip if not exists
    uint256 sizeBefore = size(list);
    remove(list, id);
    // INV-4: after remove, contains is false and size decremented by 1
    assert(!contains(list, id));
    assert(size(list) == sizeBefore - 1);
}
```

Update the harness import to include `remove` and `size` if not already there.

- [ ] **Step 2: Write invariant test contract**

Add a new contract to the test file:
```solidity
contract DoublyLinkedListInvariantTest is Test {
    DLLHarness internal harness;

    function setUp() public {
        harness = new DLLHarness();
        targetContract(address(harness));
        // Only call bounded mutation handlers
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = DLLHarness.pushBack_bounded.selector;
        selectors[1] = DLLHarness.remove_bounded.selector;
        targetSelector(FuzzSelector({addr: address(harness), selectors: selectors}));
    }

    /// @dev INV-1: size equals reachable node count from head walking next.
    function invariant_sizeMatchesReachable() public view {
        uint256 count;
        bytes32 node = harness.head_();
        while (node != SENTINEL) {
            count++;
            node = harness.next_(node);
            require(count <= 256, "infinite loop detected");
        }
        assertEq(harness.size_(), count);
    }

    /// @dev INV-2: forward and reverse traversals visit same nodes in opposite order.
    function invariant_forwardReverseSymmetry() public view {
        uint256 sz = harness.size_();
        if (sz == 0) return;

        bytes32[] memory forward = new bytes32[](sz);
        bytes32 node = harness.head_();
        for (uint256 i; i < sz; i++) {
            forward[i] = node;
            node = harness.next_(node);
        }

        node = harness.tail_();
        for (uint256 i = sz; i > 0; i--) {
            assertEq(node, forward[i - 1]);
            node = harness.prev_(node);
        }
    }

    /// @dev INV-3: contains(SENTINEL) is always false.
    function invariant_sentinelNeverContained() public view {
        assertFalse(harness.contains_(SENTINEL));
    }
}
```

- [ ] **Step 3: Run invariant tests**

Run: `forge test --match-contract DoublyLinkedListInvariantTest -v`
Expected: All 3 invariants PASS (256 default runs with random call sequences)

- [ ] **Step 4: Commit**

```bash
git add test/libraries/DoublyLinkedListLib.t.sol
git commit -m "test(dll): add invariant tests for size/traversal/sentinel properties"
```

---

### Task 9: Final verification — run full suite

**Files:** None (verification only)

- [ ] **Step 1: Run the complete test suite**

Run: `forge test --match-path test/libraries/DoublyLinkedListLib.t.sol -v`
Expected: All tests PASS (unit + fuzz + invariant)

- [ ] **Step 2: Run with gas report**

Run: `forge test --match-path test/libraries/DoublyLinkedListLib.t.sol --gas-report`
Expected: Gas numbers roughly match spec estimates (~44k cold insert, ~10k warm)

- [ ] **Step 3: Verify line counts are reasonable**

Run: `wc -l src/libraries/DoublyLinkedListLib.sol test/libraries/DoublyLinkedListLib.t.sol`
Expected: Library ~100-120 lines, tests ~250-300 lines

- [ ] **Step 4: Final commit if any cleanup needed, otherwise done**

No commit needed if nothing changed. The implementation is complete.
