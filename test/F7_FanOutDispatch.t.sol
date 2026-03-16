// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OriginEndpoint, originId} from "../src/types/OriginEndpoint.sol";
import {CallbackEndpoint, callbackId} from "../src/types/CallbackEndpoint.sol";
import {Binding, BindingState, bindingId} from "../src/types/Binding.sol";

import {
    OriginRegistryStorage,
    _originRegistryStorage,
    setOrigin,
    getOriginExists
} from "../src/modules/OriginRegistryStorageMod.sol";

import {
    CallbackRegistryStorage,
    _callbackRegistryStorage,
    setCallback,
    getCallbackExists
} from "../src/modules/CallbackRegistryStorageMod.sol";

import {
    EventDispatchStorage,
    _eventDispatchStorage,
    getBindingExists,
    getBinding,
    getBindingCountByOrigin
} from "../src/modules/EventDispatchStorageMod.sol";

import {
    validateBind,
    immediateBind,
    scheduledBind,
    pauseBind,
    resumeBind,
    dispatch
} from "../src/libraries/EventDispatchLib.sol";

/// @dev F7 integration tests — Fan-Out Dispatch.
///      Proves that dispatch() walks the DLL for an origin and returns only Active
///      callbackIds in FIFO registration order.
contract F7_FanOutDispatchTest is Test {
    bytes32 constant SWAP_SIG = keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");
    bytes32 constant MINT_SIG = keccak256("Mint(address,address,int24,int24,uint128,uint256,uint256)");
    bytes32 constant BURN_SIG = keccak256("Burn(address,int24,int24,uint128,uint256,uint256)");
    bytes32 constant COLLECT_SIG = keccak256("Collect(address,address,int24,int24,uint128,uint128)");

    function _os() internal pure returns (OriginRegistryStorage storage) { return _originRegistryStorage(); }
    function _cs() internal pure returns (CallbackRegistryStorage storage) { return _callbackRegistryStorage(); }
    function _edt() internal pure returns (EventDispatchStorage storage) { return _eventDispatchStorage(); }

    /// @dev F7.1 — Single callback dispatch.
    ///      Given: active binding (O1, C1)
    ///      When:  dispatch(O1)
    ///      Then:  returns [C1]
    function test_F7_1_single_callback_dispatch() public {
        // Register origin O1
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);

        // Register callback C1
        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x11111111), 500_000);
        bytes32 c1Id = setCallback(_cs(), c1);

        // Bind O1 -> C1 (Active)
        validateBind(_os(), _cs(), o1Id, c1Id);
        immediateBind(_edt(), o1Id, c1Id);

        // Dispatch
        bytes32[] memory results = dispatch(_edt(), o1Id);

        assertEq(results.length, 1, "must return exactly 1 callback");
        assertEq(results[0], c1Id, "must return C1");
    }

    /// @dev F7.2 — Multi-callback fan-out.
    ///      Given: active bindings (O1, C1), (O1, C2), (O1, C3)
    ///      When:  dispatch(O1)
    ///      Then:  returns [C1, C2, C3] in FIFO registration order
    function test_F7_2_multi_callback_fan_out() public {
        // Register origin O1
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);

        // Register callbacks C1, C2, C3
        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x11111111), 500_000);
        CallbackEndpoint memory c2 = CallbackEndpoint(1, address(0xCCC), bytes4(0x22222222), 500_000);
        CallbackEndpoint memory c3 = CallbackEndpoint(1, address(0xDDD), bytes4(0x33333333), 500_000);
        bytes32 c1Id = setCallback(_cs(), c1);
        bytes32 c2Id = setCallback(_cs(), c2);
        bytes32 c3Id = setCallback(_cs(), c3);

        // Bind all three in FIFO order
        validateBind(_os(), _cs(), o1Id, c1Id);
        immediateBind(_edt(), o1Id, c1Id);
        validateBind(_os(), _cs(), o1Id, c2Id);
        immediateBind(_edt(), o1Id, c2Id);
        validateBind(_os(), _cs(), o1Id, c3Id);
        immediateBind(_edt(), o1Id, c3Id);

        // Dispatch
        bytes32[] memory results = dispatch(_edt(), o1Id);

        assertEq(results.length, 3, "must return exactly 3 callbacks");
        assertEq(results[0], c1Id, "first must be C1 (FIFO)");
        assertEq(results[1], c2Id, "second must be C2 (FIFO)");
        assertEq(results[2], c3Id, "third must be C3 (FIFO)");
    }

    /// @dev F7.3 — Isolated origins.
    ///      Given: active bindings (O1, C1), (O2, C2)
    ///      When:  dispatch(O1)
    ///      Then:  returns [C1] only
    function test_F7_3_isolated_origins() public {
        // Register origins O1, O2
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        OriginEndpoint memory o2 = OriginEndpoint(1, address(0xAAA), MINT_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);
        bytes32 o2Id = setOrigin(_os(), o2);

        // Register callbacks C1, C2
        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x11111111), 500_000);
        CallbackEndpoint memory c2 = CallbackEndpoint(1, address(0xCCC), bytes4(0x22222222), 500_000);
        bytes32 c1Id = setCallback(_cs(), c1);
        bytes32 c2Id = setCallback(_cs(), c2);

        // Bind O1 -> C1, O2 -> C2
        validateBind(_os(), _cs(), o1Id, c1Id);
        immediateBind(_edt(), o1Id, c1Id);
        validateBind(_os(), _cs(), o2Id, c2Id);
        immediateBind(_edt(), o2Id, c2Id);

        // Dispatch O1 — should only return C1
        bytes32[] memory results = dispatch(_edt(), o1Id);

        assertEq(results.length, 1, "must return exactly 1 callback");
        assertEq(results[0], c1Id, "must return C1 only");

        // Verify O2 dispatch returns C2 only
        bytes32[] memory results2 = dispatch(_edt(), o2Id);
        assertEq(results2.length, 1, "O2 must return exactly 1 callback");
        assertEq(results2[0], c2Id, "O2 must return C2 only");
    }

    /// @dev F7.4 — Empty dispatch.
    ///      Given: registered origin O1 with no bindings
    ///      When:  dispatch(O1)
    ///      Then:  returns empty array
    function test_F7_4_empty_dispatch() public {
        // Register origin O1 but do NOT bind any callbacks
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);

        // Dispatch — should return empty
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 0, "must return empty array");
    }

    /// @dev F7.5 — Paused bindings skipped (F8 preview).
    ///      Given: active bindings (O1, C1), (O1, C2), C1 is paused
    ///      When:  dispatch(O1)
    ///      Then:  returns [C2] only
    function test_F7_5_paused_bindings_skipped() public {
        // Register origin O1
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);

        // Register callbacks C1, C2
        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x11111111), 500_000);
        CallbackEndpoint memory c2 = CallbackEndpoint(1, address(0xCCC), bytes4(0x22222222), 500_000);
        bytes32 c1Id = setCallback(_cs(), c1);
        bytes32 c2Id = setCallback(_cs(), c2);

        // Bind both
        validateBind(_os(), _cs(), o1Id, c1Id);
        bytes32 bId1 = immediateBind(_edt(), o1Id, c1Id);
        validateBind(_os(), _cs(), o1Id, c2Id);
        immediateBind(_edt(), o1Id, c2Id);

        // Pause C1's binding
        pauseBind(_edt(), bId1);

        // Dispatch — should skip C1
        bytes32[] memory results = dispatch(_edt(), o1Id);

        assertEq(results.length, 1, "must return exactly 1 callback");
        assertEq(results[0], c2Id, "must return C2 only (C1 is paused)");
    }

    /// @dev F7.6 — PendingFunding bindings skipped.
    ///      Given: binding (O1, C1) in PendingFunding state
    ///      When:  dispatch(O1)
    ///      Then:  returns empty array
    function test_F7_6_pending_funding_skipped() public {
        // Register origin O1
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);

        // Register callback C1
        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x11111111), 500_000);
        bytes32 c1Id = setCallback(_cs(), c1);

        // Scheduled bind — creates PendingFunding state
        validateBind(_os(), _cs(), o1Id, c1Id);
        scheduledBind(_edt(), o1Id, c1Id);

        // Dispatch — should return empty (PendingFunding is not Active)
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 0, "must return empty array (PendingFunding skipped)");
    }
}
