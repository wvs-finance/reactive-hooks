// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OriginEndpoint, originId} from "../src/types/OriginEndpoint.sol";
import {CallbackEndpoint, callbackId} from "../src/types/CallbackEndpoint.sol";
import {Binding, BindingState, bindingId, OriginNotRegistered, CallbackNotRegistered, InsufficientFunds} from "../src/types/Binding.sol";

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
    quoteBind,
    fundedBind,
    SUBSCRIPTION_COST_ESTIMATE
} from "../src/libraries/EventDispatchLib.sol";

/// @dev F10 integration tests — Quote-Then-Fund Safety.
///      Proves the quote-then-fund pattern prevents ETH loss on validation failure.
///      ALL validation checks happen BEFORE any funds are sent to SystemContract.
///      Per reactive-smart-contracts skill: Reactive Network keeps ETH on revert,
///      so we MUST validate before sending any funds.
contract F10_QuoteThenFundTest is Test {
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

    /// @dev F10.1 — quoteBind returns cost for first binding on origin.
    ///      Origin O1 has no bindings yet, so subscription cost applies.
    function test_F10_1_quoteBind_returns_cost_for_first_binding() public view {
        uint256 cost = quoteBind(_edt(), _os(), o1Id);
        assertEq(cost, SUBSCRIPTION_COST_ESTIMATE, "first binding must cost SUBSCRIPTION_COST_ESTIMATE");
    }

    /// @dev F10.2 — quoteBind returns 0 for already-subscribed origin.
    ///      After binding O1->C1, a second binding O1->C2 costs 0.
    function test_F10_2_quoteBind_returns_zero_for_subscribed_origin() public {
        // Create first binding to establish subscription
        immediateBind(_edt(), o1Id, c1Id);

        // Quote second binding — should be free
        uint256 cost = quoteBind(_edt(), _os(), o1Id);
        assertEq(cost, 0, "already-subscribed origin must cost 0");
    }

    /// @dev F10.3 — fundedBind succeeds with sufficient balance.
    ///      Creates Active binding and returns cost.
    function test_F10_3_fundedBind_succeeds_with_sufficient_balance() public {
        (bytes32 bId, uint256 cost) = fundedBind(
            _edt(), _os(), _cs(), o1Id, c1Id, 1 ether
        );

        // Verify binding exists and is Active
        assertTrue(getBindingExists(_edt(), bId), "binding must exist");
        Binding storage b = getBinding(_edt(), bId);
        assertEq(uint8(b.state), uint8(BindingState.Active), "state must be Active");
        assertEq(b.originId, o1Id, "originId must match");
        assertEq(b.callbackId, c1Id, "callbackId must match");
        assertEq(cost, SUBSCRIPTION_COST_ESTIMATE, "cost must be SUBSCRIPTION_COST_ESTIMATE");
    }

    /// @dev F10.4 — fundedBind reverts on insufficient balance.
    ///      No state changes occur — binding is NOT created.
    function test_F10_4_fundedBind_reverts_on_insufficient_balance() public {
        uint256 countBefore = getBindingCountByOrigin(_edt(), o1Id);

        vm.expectRevert(
            abi.encodeWithSelector(InsufficientFunds.selector, SUBSCRIPTION_COST_ESTIMATE, 0)
        );
        this.externalFundedBind(o1Id, c1Id, 0);

        // Verify NO state changes occurred
        uint256 countAfter = getBindingCountByOrigin(_edt(), o1Id);
        assertEq(countBefore, countAfter, "binding count must not change on revert");
    }

    /// @dev F10.5 — fundedBind reverts on unregistered origin BEFORE balance check.
    ///      Validation failure happens first, balance is irrelevant.
    function test_F10_5_fundedBind_reverts_on_unregistered_origin() public {
        bytes32 fakeOriginId = keccak256("fake-origin");

        vm.expectRevert(
            abi.encodeWithSelector(OriginNotRegistered.selector, fakeOriginId)
        );
        this.externalFundedBind(fakeOriginId, c1Id, 1 ether);
    }

    /// @dev F10.6 — Second bind on same origin costs 0.
    ///      After O1->C1 exists, O1->C2 succeeds with cost=0 even with 0 balance.
    function test_F10_6_second_bind_costs_zero() public {
        // First bind — establishes subscription
        fundedBind(_edt(), _os(), _cs(), o1Id, c1Id, 1 ether);

        // Second bind on same origin — costs 0, succeeds with 0 balance
        (bytes32 bId, uint256 cost) = fundedBind(
            _edt(), _os(), _cs(), o1Id, c2Id, 0
        );

        assertEq(cost, 0, "second binding on same origin must cost 0");
        assertTrue(getBindingExists(_edt(), bId), "second binding must exist");
        Binding storage b = getBinding(_edt(), bId);
        assertEq(uint8(b.state), uint8(BindingState.Active), "state must be Active");
    }

    /// @dev External wrapper for fundedBind so vm.expectRevert works with free functions.
    function externalFundedBind(
        bytes32 _originId,
        bytes32 _callbackId,
        uint256 availableBalance
    ) external returns (bytes32, uint256) {
        return fundedBind(_edt(), _os(), _cs(), _originId, _callbackId, availableBalance);
    }
}
