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
