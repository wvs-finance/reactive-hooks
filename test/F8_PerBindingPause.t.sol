// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {OriginEndpoint} from "../src/types/OriginEndpoint.sol";
import {CallbackEndpoint} from "../src/types/CallbackEndpoint.sol";
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
    getBinding
} from "../src/modules/EventDispatchStorageMod.sol";

import {
    validateBind,
    immediateBind,
    pauseBind,
    resumeBind,
    dispatch
} from "../src/libraries/EventDispatchLib.sol";

/// @dev F8 — Per-Binding Pause test suite.
///      Proves that pause/resume controls dispatch inclusion without affecting
///      origin subscription or binding existence.
contract F8_PerBindingPauseTest is Test {
    // --- Test fixtures ---
    bytes32 constant SWAP_SIG = keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");
    bytes32 constant MINT_SIG = keccak256("Mint(address,address,int24,int24,uint128,uint256,uint256)");

    address constant EMITTER = address(0xAAA);
    address constant TARGET_1 = address(0xBB1);
    address constant TARGET_2 = address(0xBB2);

    bytes4 constant SEL_1 = bytes4(keccak256("onSwap(bytes)"));
    bytes4 constant SEL_2 = bytes4(keccak256("onMint(bytes)"));

    // Precomputed IDs (set in setUp)
    bytes32 internal s_originId;
    bytes32 internal s_callbackId1;
    bytes32 internal s_callbackId2;
    bytes32 internal s_bindingId1;
    bytes32 internal s_bindingId2;

    // --- Storage accessors (SCOP: no modifier, no public) ---

    function _os() internal pure returns (OriginRegistryStorage storage) {
        return _originRegistryStorage();
    }

    function _cs() internal pure returns (CallbackRegistryStorage storage) {
        return _callbackRegistryStorage();
    }

    function _edt() internal pure returns (EventDispatchStorage storage) {
        return _eventDispatchStorage();
    }

    // --- setUp ---

    function setUp() external {
        // Register origin O1
        OriginEndpoint memory o1 = OriginEndpoint(1, EMITTER, SWAP_SIG);
        s_originId = setOrigin(_os(), o1);

        // Register callbacks C1, C2
        CallbackEndpoint memory c1 = CallbackEndpoint(1, TARGET_1, SEL_1, 500_000);
        CallbackEndpoint memory c2 = CallbackEndpoint(1, TARGET_2, SEL_2, 500_000);
        s_callbackId1 = setCallback(_cs(), c1);
        s_callbackId2 = setCallback(_cs(), c2);

        // Validate and bind both
        validateBind(_os(), _cs(), s_originId, s_callbackId1);
        s_bindingId1 = immediateBind(_edt(), s_originId, s_callbackId1);

        validateBind(_os(), _cs(), s_originId, s_callbackId2);
        s_bindingId2 = immediateBind(_edt(), s_originId, s_callbackId2);
    }

    // ══════════════════════════════════════════════
    // F8.1 — Pause excludes from dispatch
    // ══════════════════════════════════════════════

    function test_F8_1_pauseExcludesFromDispatch() external {
        // Pre-condition: both callbacks dispatched
        bytes32[] memory before = dispatch(_edt(), s_originId);
        assertEq(before.length, 2, "pre: 2 active");

        // Pause binding for C1
        pauseBind(_edt(), s_bindingId1);

        // Dispatch should return only C2
        bytes32[] memory postPause = dispatch(_edt(), s_originId);
        assertEq(postPause.length, 1, "post: 1 active");
        assertEq(postPause[0], s_callbackId2, "only C2 dispatched");
    }

    // ══════════════════════════════════════════════
    // F8.2 — Resume re-includes in dispatch
    // ══════════════════════════════════════════════

    function test_F8_2_resumeReincludesInDispatch() external {
        // Pause C1
        pauseBind(_edt(), s_bindingId1);

        // Verify only C2 dispatched
        bytes32[] memory paused = dispatch(_edt(), s_originId);
        assertEq(paused.length, 1, "paused: 1 active");

        // Resume C1
        resumeBind(_edt(), s_bindingId1);

        // Both should be dispatched again
        bytes32[] memory resumed = dispatch(_edt(), s_originId);
        assertEq(resumed.length, 2, "resumed: 2 active");
        assertEq(resumed[0], s_callbackId1, "C1 first (FIFO)");
        assertEq(resumed[1], s_callbackId2, "C2 second (FIFO)");
    }

    // ══════════════════════════════════════════════
    // F8.3 — Pause does not affect origin subscription
    // ══════════════════════════════════════════════

    function test_F8_3_pauseDoesNotAffectOrigin() external {
        // Pause C1
        pauseBind(_edt(), s_bindingId1);

        // Origin still registered
        assertTrue(getOriginExists(_os(), s_originId), "origin still registered");

        // Binding still exists
        assertTrue(getBindingExists(_edt(), s_bindingId1), "binding still exists");

        // Binding state is Paused
        Binding storage b = getBinding(_edt(), s_bindingId1);
        assertEq(uint256(b.state), uint256(BindingState.Paused), "state=Paused");

        // Other binding unaffected
        Binding storage b2 = getBinding(_edt(), s_bindingId2);
        assertEq(uint256(b2.state), uint256(BindingState.Active), "C2 still Active");

        // Dispatch still works (just returns C2)
        bytes32[] memory result = dispatch(_edt(), s_originId);
        assertEq(result.length, 1, "dispatch returns 1");
        assertEq(result[0], s_callbackId2, "C2 dispatched");
    }

    // ══════════════════════════════════════════════
    // F8.4 — Pause all callbacks — dispatch returns empty, origin persists
    // ══════════════════════════════════════════════

    function test_F8_4_pauseAllCallbacks() external {
        // Pause both bindings
        pauseBind(_edt(), s_bindingId1);
        pauseBind(_edt(), s_bindingId2);

        // Dispatch returns empty
        bytes32[] memory result = dispatch(_edt(), s_originId);
        assertEq(result.length, 0, "dispatch returns empty");

        // Origin still registered
        assertTrue(getOriginExists(_os(), s_originId), "origin persists");

        // Both bindings still exist with state=Paused
        assertTrue(getBindingExists(_edt(), s_bindingId1), "binding1 exists");
        assertTrue(getBindingExists(_edt(), s_bindingId2), "binding2 exists");
        assertEq(uint256(getBinding(_edt(), s_bindingId1).state), uint256(BindingState.Paused), "b1 Paused");
        assertEq(uint256(getBinding(_edt(), s_bindingId2).state), uint256(BindingState.Paused), "b2 Paused");
    }

    // ══════════════════════════════════════════════
    // F8.5 — Pause is idempotent
    // ══════════════════════════════════════════════

    function test_F8_5_pauseIdempotent() external {
        // Pause once
        pauseBind(_edt(), s_bindingId1);
        assertEq(uint256(getBinding(_edt(), s_bindingId1).state), uint256(BindingState.Paused), "first pause");

        // Pause again — no revert
        pauseBind(_edt(), s_bindingId1);
        assertEq(uint256(getBinding(_edt(), s_bindingId1).state), uint256(BindingState.Paused), "second pause");

        // Dispatch still correct
        bytes32[] memory result = dispatch(_edt(), s_originId);
        assertEq(result.length, 1, "still 1 active");
        assertEq(result[0], s_callbackId2, "C2 dispatched");
    }

    // ══════════════════════════════════════════════
    // F8.6 — Resume is idempotent
    // ══════════════════════════════════════════════

    function test_F8_6_resumeIdempotent() external {
        // Both already Active — resume should not revert
        resumeBind(_edt(), s_bindingId1);
        assertEq(uint256(getBinding(_edt(), s_bindingId1).state), uint256(BindingState.Active), "still Active");

        // Resume again — still no revert
        resumeBind(_edt(), s_bindingId1);
        assertEq(uint256(getBinding(_edt(), s_bindingId1).state), uint256(BindingState.Active), "still Active x2");

        // Dispatch unchanged
        bytes32[] memory result = dispatch(_edt(), s_originId);
        assertEq(result.length, 2, "2 active");
    }
}
