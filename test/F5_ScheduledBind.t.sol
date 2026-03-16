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
    getBindingCountByOrigin,
    isBindingInOrigin,
    getBindingTotalCount
} from "../src/modules/EventDispatchStorageMod.sol";

import {
    validateBind,
    immediateBind,
    scheduledBind,
    resumeBind,
    dispatch
} from "../src/libraries/EventDispatchLib.sol";

/// @dev F5 integration tests -- Scheduled Bind (PendingFunding) flow.
///      Proves that scheduledBind() creates PendingFunding bindings that are
///      excluded from dispatch until manually resumed via resumeBind().
contract F5_ScheduledBindTest is Test {
    bytes32 constant SWAP_SIG = keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");
    bytes32 constant MINT_SIG = keccak256("Mint(address,address,int24,int24,uint128,uint256,uint256)");

    bytes32 internal o1Id;
    bytes32 internal c1Id;
    bytes32 internal c2Id;

    function _os() internal pure returns (OriginRegistryStorage storage) { return _originRegistryStorage(); }
    function _cs() internal pure returns (CallbackRegistryStorage storage) { return _callbackRegistryStorage(); }
    function _edt() internal pure returns (EventDispatchStorage storage) { return _eventDispatchStorage(); }

    function setUp() public {
        // Register origin O1
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        o1Id = setOrigin(_os(), o1);

        // Register callback C1
        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x12345678), 500_000);
        c1Id = setCallback(_cs(), c1);

        // Register callback C2
        CallbackEndpoint memory c2 = CallbackEndpoint(1, address(0xCCC), bytes4(0xAABBCCDD), 500_000);
        c2Id = setCallback(_cs(), c2);
    }

    /// @dev F5.1 -- Successful scheduled bind.
    ///      Creates a PendingFunding binding without requiring funds.
    ///      No subscription activated (no SystemContract call, no revert from missing SC).
    function test_F5_1_successful_scheduled_bind() public {
        validateBind(_os(), _cs(), o1Id, c1Id);

        bytes32 bId = scheduledBind(_edt(), o1Id, c1Id);

        // Binding exists
        assertTrue(getBindingExists(_edt(), bId), "binding must exist");

        // State is PendingFunding
        Binding storage b = getBinding(_edt(), bId);
        assertEq(uint8(b.state), uint8(BindingState.PendingFunding), "state must be PendingFunding");
        assertEq(b.originId, o1Id, "originId must match");
        assertEq(b.callbackId, c1Id, "callbackId must match");

        // In fan-out list
        assertTrue(isBindingInOrigin(_edt(), o1Id, bId), "binding must be in origin fan-out");
        assertEq(getBindingCountByOrigin(_edt(), o1Id), 1, "fan-out count must be 1");
    }

    /// @dev F5.2 -- PendingFunding binding not in dispatch results.
    ///      dispatch(O1) must return empty when only PendingFunding bindings exist.
    function test_F5_2_pending_funding_not_dispatched() public {
        validateBind(_os(), _cs(), o1Id, c1Id);
        scheduledBind(_edt(), o1Id, c1Id);

        bytes32[] memory results = dispatch(_edt(), o1Id);

        assertEq(results.length, 0, "PendingFunding binding must not appear in dispatch");
    }

    /// @dev F5.3 -- Manual resume activates scheduled bind.
    ///      After resumeBind(), state transitions to Active and dispatch includes it.
    function test_F5_3_resume_activates_scheduled_bind() public {
        validateBind(_os(), _cs(), o1Id, c1Id);
        bytes32 bId = scheduledBind(_edt(), o1Id, c1Id);

        // Verify PendingFunding before resume
        assertEq(uint8(getBinding(_edt(), bId).state), uint8(BindingState.PendingFunding), "pre: must be PendingFunding");

        // Resume
        resumeBind(_edt(), bId);

        // State is now Active
        assertEq(uint8(getBinding(_edt(), bId).state), uint8(BindingState.Active), "post: must be Active");

        // Dispatch now includes C1
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 1, "dispatch must return 1 callback");
        assertEq(results[0], c1Id, "dispatch must return C1");
    }

    /// @dev F5.4 -- Scheduled bind is idempotent.
    ///      Calling scheduledBind() again on the same pair returns same bindingId, no revert.
    function test_F5_4_scheduled_bind_idempotent() public {
        validateBind(_os(), _cs(), o1Id, c1Id);
        bytes32 bId1 = scheduledBind(_edt(), o1Id, c1Id);

        // Bind again
        bytes32 bId2 = scheduledBind(_edt(), o1Id, c1Id);

        assertEq(bId1, bId2, "binding IDs must match");
        assertEq(getBindingCountByOrigin(_edt(), o1Id), 1, "fan-out count must still be 1");
        assertEq(getBindingTotalCount(_edt()), 1, "total count must still be 1");
    }

    /// @dev F5.5 -- Mixed states: immediate + scheduled on same origin.
    ///      dispatch(O1) returns only the Active binding, skips PendingFunding.
    function test_F5_5_mixed_immediate_and_scheduled() public {
        validateBind(_os(), _cs(), o1Id, c1Id);
        validateBind(_os(), _cs(), o1Id, c2Id);

        // C1 = Active (immediate bind)
        immediateBind(_edt(), o1Id, c1Id);

        // C2 = PendingFunding (scheduled bind)
        scheduledBind(_edt(), o1Id, c2Id);

        // Dispatch should only return C1
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 1, "dispatch must return 1 callback (Active only)");
        assertEq(results[0], c1Id, "dispatch must return C1 (Active), not C2 (PendingFunding)");

        // Verify both bindings exist
        assertEq(getBindingCountByOrigin(_edt(), o1Id), 2, "fan-out count must be 2 (both exist)");
    }
}
