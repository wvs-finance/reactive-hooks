// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DLL, SENTINEL, PREV, NEXT, contains, isEmpty, size, head, tail, pushBack, pushFront, next, prev, remove, insertAfter, insertBefore, InvalidNode, NodeAlreadyExists, NodeDoesNotExist} from "../../src/libraries/DoublyLinkedListLib.sol";

contract DLLHarness {
    DLL internal list;

    function contains_(bytes32 id) external view returns (bool) { return contains(list, id); }
    function isEmpty_() external view returns (bool) { return isEmpty(list); }
    function size_() external view returns (uint256) { return size(list); }
    function head_() external view returns (bytes32) { return head(list); }
    function tail_() external view returns (bytes32) { return tail(list); }
    function pushBack_(bytes32 id) external { pushBack(list, id); }
    function pushFront_(bytes32 id) external { pushFront(list, id); }
    function next_(bytes32 id) external view returns (bytes32) { return next(list, id); }
    function prev_(bytes32 id) external view returns (bytes32) { return prev(list, id); }
    function remove_(bytes32 id) external { remove(list, id); }
    function insertAfter_(bytes32 anchor, bytes32 id) external { insertAfter(list, anchor, id); }
    function insertBefore_(bytes32 anchor, bytes32 id) external { insertBefore(list, anchor, id); }

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
}

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
