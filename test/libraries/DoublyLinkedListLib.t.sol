// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DLL, SENTINEL, PREV, NEXT, contains, isEmpty, size, head, tail, pushBack, pushFront, next, prev, remove, InvalidNode, NodeAlreadyExists, NodeDoesNotExist} from "../../src/libraries/DoublyLinkedListLib.sol";

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
}
