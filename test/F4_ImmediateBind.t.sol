// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OriginEndpoint, originId} from "../src/types/OriginEndpoint.sol";
import {CallbackEndpoint, callbackId} from "../src/types/CallbackEndpoint.sol";
import {Binding, BindingState, bindingId, OriginNotRegistered, CallbackNotRegistered} from "../src/types/Binding.sol";

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
    getBindingCountByOrigin,
    isBindingInOrigin,
    getBindingTotalCount
} from "../src/modules/EventDispatchStorageMod.sol";

import {
    validateBind,
    immediateBind,
    scheduledBind,
    pauseBind,
    resumeBind
} from "../src/libraries/EventDispatchLib.sol";

/// @dev F4 integration tests — Immediate Bind flow.
///      Per reactive-smart-contracts skill: SystemContract can't be simulated in Foundry,
///      so we test binding logic (validation, state, fan-out) separately from subscription
///      activation. Subscription integration is verified on Reactive Network deployment.
contract F4_ImmediateBindTest is Test {
    bytes32 constant SWAP_SIG = keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");
    bytes32 constant MINT_SIG = keccak256("Mint(address,address,int24,int24,uint128,uint256,uint256)");

    bytes32 internal o1Id;
    bytes32 internal c1Id;

    function _os() internal pure returns (OriginRegistryStorage storage) { return _originRegistryStorage(); }
    function _cs() internal pure returns (CallbackRegistryStorage storage) { return _callbackRegistryStorage(); }
    function _edt() internal pure returns (EventDispatchStorage storage) { return _eventDispatchStorage(); }

    function setUp() public {
        // Register origin O₁
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        o1Id = setOrigin(_os(), o1);

        // Register callback C₁
        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x12345678), 500_000);
        c1Id = setCallback(_cs(), c1);
    }

    /// @dev F4.1 — Successful immediate bind.
    ///      Validates origin/callback exist, creates Active binding, discoverable by bindingId.
    ///      NOTE: Subscription activation (subscribe() call to SystemContract) is NOT tested here.
    ///      Per reactive-smart-contracts skill, SystemContract can't be simulated in Foundry.
    function test_F4_1_successful_immediate_bind() public {
        // Validate — quote phase (all checks before any state change)
        validateBind(_os(), _cs(), o1Id, c1Id);

        // Bind — creates Active binding
        bytes32 bId = immediateBind(_edt(), o1Id, c1Id);

        // Verify binding exists and is Active
        assertTrue(getBindingExists(_edt(), bId), "binding must exist");
        Binding storage b = getBinding(_edt(), bId);
        assertEq(uint8(b.state), uint8(BindingState.Active), "state must be Active");
        assertEq(b.originId, o1Id, "originId must match");
        assertEq(b.callbackId, c1Id, "callbackId must match");

        // Verify discoverable in fan-out list
        assertTrue(isBindingInOrigin(_edt(), o1Id, bId), "binding must be in origin's fan-out");
        assertEq(getBindingCountByOrigin(_edt(), o1Id), 1, "fan-out count must be 1");
    }

    /// @dev F4.2 — Revert on unregistered origin.
    ///      Quote-then-fund: validation reverts BEFORE any ETH is sent.
    ///      Uses external call wrapper since free functions can't be caught by vm.expectRevert.
    function test_F4_2_revert_on_unregistered_origin() public {
        bytes32 fakeOriginId = keccak256("fake-origin");

        vm.expectRevert(abi.encodeWithSelector(OriginNotRegistered.selector, fakeOriginId));
        this.externalValidateBind(fakeOriginId, c1Id);
    }

    /// @dev F4.3 — Revert on unregistered origin (different fake ID).
    function test_F4_3_revert_on_unregistered_origin() public {
        bytes32 fakeOriginId = keccak256("nonexistent");

        vm.expectRevert(abi.encodeWithSelector(OriginNotRegistered.selector, fakeOriginId));
        this.externalValidateBind(fakeOriginId, c1Id);
    }

    /// @dev F4.4 — Revert on unregistered callback.
    function test_F4_4_revert_on_unregistered_callback() public {
        bytes32 fakeCallbackId = keccak256("fake-callback");

        vm.expectRevert(abi.encodeWithSelector(CallbackNotRegistered.selector, fakeCallbackId));
        this.externalValidateBind(o1Id, fakeCallbackId);
    }

    /// @dev External wrapper for validateBind so vm.expectRevert works.
    function externalValidateBind(bytes32 _originId, bytes32 _callbackId) external view {
        validateBind(_os(), _cs(), _originId, _callbackId);
    }

    /// @dev F4.5 — Duplicate bind is idempotent.
    function test_F4_5_duplicate_bind_idempotent() public {
        validateBind(_os(), _cs(), o1Id, c1Id);
        bytes32 bId1 = immediateBind(_edt(), o1Id, c1Id);

        // Bind again — should be idempotent
        bytes32 bId2 = immediateBind(_edt(), o1Id, c1Id);

        assertEq(bId1, bId2, "binding IDs must match");
        assertEq(getBindingCountByOrigin(_edt(), o1Id), 1, "fan-out count must still be 1");
        assertEq(getBindingTotalCount(_edt()), 1, "total count must still be 1");
    }

    /// @dev F4 bonus — bindingId is deterministic from origin+callback pair.
    function test_F4_bindingId_deterministic() public pure {
        bytes32 oId = keccak256("origin");
        bytes32 cId = keccak256("callback");
        assertEq(bindingId(oId, cId), bindingId(oId, cId));
    }

    /// @dev F4 bonus — validateBind does NOT modify state (view function).
    ///      This proves the "quote" phase is side-effect-free.
    function test_F4_validateBind_is_side_effect_free() public {
        uint256 totalBefore = getBindingTotalCount(_edt());

        validateBind(_os(), _cs(), o1Id, c1Id);

        uint256 totalAfter = getBindingTotalCount(_edt());
        assertEq(totalBefore, totalAfter, "validateBind must not change state");
    }

    /// @dev F5.1 preview — Scheduled bind creates PendingFunding state.
    function test_F5_1_scheduled_bind_pending_funding() public {
        validateBind(_os(), _cs(), o1Id, c1Id);
        bytes32 bId = scheduledBind(_edt(), o1Id, c1Id);

        Binding storage b = getBinding(_edt(), bId);
        assertEq(uint8(b.state), uint8(BindingState.PendingFunding), "state must be PendingFunding");
    }

    /// @dev F8.1 preview — Pause changes state without affecting existence.
    function test_F8_1_pause_binding() public {
        validateBind(_os(), _cs(), o1Id, c1Id);
        bytes32 bId = immediateBind(_edt(), o1Id, c1Id);

        pauseBind(_edt(), bId);

        Binding storage b = getBinding(_edt(), bId);
        assertEq(uint8(b.state), uint8(BindingState.Paused), "state must be Paused");
        assertTrue(getBindingExists(_edt(), bId), "binding must still exist");
    }

    /// @dev F8.2 preview — Resume restores Active state.
    function test_F8_2_resume_binding() public {
        validateBind(_os(), _cs(), o1Id, c1Id);
        bytes32 bId = immediateBind(_edt(), o1Id, c1Id);

        pauseBind(_edt(), bId);
        resumeBind(_edt(), bId);

        Binding storage b = getBinding(_edt(), bId);
        assertEq(uint8(b.state), uint8(BindingState.Active), "state must be Active after resume");
    }
}
