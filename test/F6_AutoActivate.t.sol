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
    pauseBind,
    resumeBind,
    activatePendingBindings,
    dispatch
} from "../src/libraries/EventDispatchLib.sol";

/// @dev F6 integration tests -- Auto-Activate via Self-Sync.
///      Proves that activatePendingBindings() walks all bindings for an origin
///      and transitions PendingFunding bindings to Active in FIFO order,
///      consuming costPerActivation from availableFunds until exhausted.
contract F6_AutoActivateTest is Test {
    bytes32 constant SWAP_SIG = keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");

    bytes32 internal o1Id;
    bytes32 internal c1Id;
    bytes32 internal c2Id;
    bytes32 internal c3Id;

    function _os() internal pure returns (OriginRegistryStorage storage) { return _originRegistryStorage(); }
    function _cs() internal pure returns (CallbackRegistryStorage storage) { return _callbackRegistryStorage(); }
    function _edt() internal pure returns (EventDispatchStorage storage) { return _eventDispatchStorage(); }

    function setUp() external {
        // Register origin O1
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        o1Id = setOrigin(_os(), o1);

        // Register callback C1
        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x11111111), 500_000);
        c1Id = setCallback(_cs(), c1);

        // Register callback C2
        CallbackEndpoint memory c2 = CallbackEndpoint(1, address(0xCCC), bytes4(0x22222222), 500_000);
        c2Id = setCallback(_cs(), c2);

        // Register callback C3
        CallbackEndpoint memory c3 = CallbackEndpoint(1, address(0xDDD), bytes4(0x33333333), 500_000);
        c3Id = setCallback(_cs(), c3);
    }

    /// @dev F6.1 -- Funding activates PendingFunding binding.
    ///      scheduledBind creates PendingFunding, then activatePendingBindings
    ///      transitions to Active when funding is sufficient.
    function test_F6_1_funding_activates_pending_binding() external {
        validateBind(_os(), _cs(), o1Id, c1Id);
        bytes32 bId = scheduledBind(_edt(), o1Id, c1Id);

        // Pre-condition: PendingFunding
        assertEq(uint8(getBinding(_edt(), bId).state), uint8(BindingState.PendingFunding), "pre: must be PendingFunding");

        // Activate with sufficient funds
        uint256 activated = activatePendingBindings(_edt(), o1Id, 1 ether, 0.01 ether);

        // Post-condition: Active
        assertEq(uint8(getBinding(_edt(), bId).state), uint8(BindingState.Active), "post: must be Active");
        assertEq(activated, 1, "activated count must be 1");

        // Dispatch now returns C1
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 1, "dispatch must return 1 callback");
        assertEq(results[0], c1Id, "dispatch must return C1");
    }

    /// @dev F6.2 -- Partial funding activates subset in FIFO order.
    ///      Only enough funds for 2 of 3 PendingFunding bindings.
    function test_F6_2_partial_funding_activates_subset() external {
        validateBind(_os(), _cs(), o1Id, c1Id);
        validateBind(_os(), _cs(), o1Id, c2Id);
        validateBind(_os(), _cs(), o1Id, c3Id);

        scheduledBind(_edt(), o1Id, c1Id);
        scheduledBind(_edt(), o1Id, c2Id);
        scheduledBind(_edt(), o1Id, c3Id);

        // Fund enough for 2 activations (0.02 ether at 0.01 each)
        uint256 activated = activatePendingBindings(_edt(), o1Id, 0.02 ether, 0.01 ether);

        assertEq(activated, 2, "activated count must be 2");

        // C1 and C2 activated (FIFO), C3 remains PendingFunding
        bytes32 bId1 = bindingId(o1Id, c1Id);
        bytes32 bId2 = bindingId(o1Id, c2Id);
        bytes32 bId3 = bindingId(o1Id, c3Id);

        assertEq(uint8(getBinding(_edt(), bId1).state), uint8(BindingState.Active), "C1 must be Active");
        assertEq(uint8(getBinding(_edt(), bId2).state), uint8(BindingState.Active), "C2 must be Active");
        assertEq(uint8(getBinding(_edt(), bId3).state), uint8(BindingState.PendingFunding), "C3 must remain PendingFunding");

        // Dispatch returns C1 and C2 only
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 2, "dispatch must return 2 callbacks");
        assertEq(results[0], c1Id, "dispatch[0] must be C1");
        assertEq(results[1], c2Id, "dispatch[1] must be C2");
    }

    /// @dev F6.3 -- Zero funding activates nothing.
    function test_F6_3_zero_funding_activates_nothing() external {
        validateBind(_os(), _cs(), o1Id, c1Id);
        bytes32 bId = scheduledBind(_edt(), o1Id, c1Id);

        uint256 activated = activatePendingBindings(_edt(), o1Id, 0, 0.01 ether);

        assertEq(activated, 0, "activated count must be 0");
        assertEq(uint8(getBinding(_edt(), bId).state), uint8(BindingState.PendingFunding), "must remain PendingFunding");
    }

    /// @dev F6.4 -- No PendingFunding bindings is a no-op.
    ///      Already-Active bindings are skipped.
    function test_F6_4_no_pending_bindings_is_noop() external {
        validateBind(_os(), _cs(), o1Id, c1Id);
        immediateBind(_edt(), o1Id, c1Id);

        uint256 activated = activatePendingBindings(_edt(), o1Id, 1 ether, 0.01 ether);

        assertEq(activated, 0, "activated count must be 0 (already active)");
    }

    /// @dev F6.5 -- Mixed states: only PendingFunding bindings are activated.
    ///      Active stays Active, Paused stays Paused, PendingFunding transitions to Active.
    function test_F6_5_mixed_states_only_pending_activated() external {
        validateBind(_os(), _cs(), o1Id, c1Id);
        validateBind(_os(), _cs(), o1Id, c2Id);

        // C1 = Active via immediateBind, then paused
        bytes32 bId1 = immediateBind(_edt(), o1Id, c1Id);
        pauseBind(_edt(), bId1);

        // C2 = PendingFunding via scheduledBind
        bytes32 bId2 = scheduledBind(_edt(), o1Id, c2Id);

        // Activate with plenty of funds
        uint256 activated = activatePendingBindings(_edt(), o1Id, 1 ether, 0.01 ether);

        assertEq(activated, 1, "activated count must be 1 (only C2)");

        // C1 remains Paused
        assertEq(uint8(getBinding(_edt(), bId1).state), uint8(BindingState.Paused), "C1 must remain Paused");

        // C2 is now Active
        assertEq(uint8(getBinding(_edt(), bId2).state), uint8(BindingState.Active), "C2 must be Active");

        // Dispatch returns only C2 (C1 still paused)
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 1, "dispatch must return 1 callback");
        assertEq(results[0], c2Id, "dispatch must return C2");
    }

    /// @dev F6.6 -- Sufficient funding for all PendingFunding bindings.
    ///      All 3 bindings activated, dispatch returns all 3 in FIFO order.
    function test_F6_6_sufficient_funding_for_all() external {
        validateBind(_os(), _cs(), o1Id, c1Id);
        validateBind(_os(), _cs(), o1Id, c2Id);
        validateBind(_os(), _cs(), o1Id, c3Id);

        scheduledBind(_edt(), o1Id, c1Id);
        scheduledBind(_edt(), o1Id, c2Id);
        scheduledBind(_edt(), o1Id, c3Id);

        // Fund enough for all 3 (0.03 ether at 0.01 each)
        uint256 activated = activatePendingBindings(_edt(), o1Id, 0.03 ether, 0.01 ether);

        assertEq(activated, 3, "activated count must be 3");

        // All bindings Active
        bytes32 bId1 = bindingId(o1Id, c1Id);
        bytes32 bId2 = bindingId(o1Id, c2Id);
        bytes32 bId3 = bindingId(o1Id, c3Id);

        assertEq(uint8(getBinding(_edt(), bId1).state), uint8(BindingState.Active), "C1 must be Active");
        assertEq(uint8(getBinding(_edt(), bId2).state), uint8(BindingState.Active), "C2 must be Active");
        assertEq(uint8(getBinding(_edt(), bId3).state), uint8(BindingState.Active), "C3 must be Active");

        // Dispatch returns all 3 in FIFO order
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 3, "dispatch must return 3 callbacks");
        assertEq(results[0], c1Id, "dispatch[0] must be C1");
        assertEq(results[1], c2Id, "dispatch[1] must be C2");
        assertEq(results[2], c3Id, "dispatch[2] must be C3");
    }
}
