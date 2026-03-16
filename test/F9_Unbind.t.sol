// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OriginEndpoint, originId} from "../src/types/OriginEndpoint.sol";
import {CallbackEndpoint, callbackId} from "../src/types/CallbackEndpoint.sol";
import {Binding, BindingState, bindingId, BindingNotFound} from "../src/types/Binding.sol";

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
    getBindingTotalCount
} from "../src/modules/EventDispatchStorageMod.sol";

import {
    validateBind,
    immediateBind,
    unbind,
    dispatch
} from "../src/libraries/EventDispatchLib.sol";

/// @dev F9 integration tests — Unbind (callback removal, origin persists).
///      Proves that unbind() removes the callback routing but the origin subscription
///      persists (independent lifecycle per design decision Q8-B).
contract F9_UnbindTest is Test {
    bytes32 constant SWAP_SIG = keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");
    bytes32 constant MINT_SIG = keccak256("Mint(address,address,int24,int24,uint128,uint256,uint256)");

    function _os() internal pure returns (OriginRegistryStorage storage) { return _originRegistryStorage(); }
    function _cs() internal pure returns (CallbackRegistryStorage storage) { return _callbackRegistryStorage(); }
    function _edt() internal pure returns (EventDispatchStorage storage) { return _eventDispatchStorage(); }

    /// @dev F9.1 — Unbind removes from dispatch.
    ///      Given: active bindings (O1, C1), (O1, C2)
    ///      When:  unbind(O1, C1)
    ///      When:  dispatch(O1)
    ///      Then:  returns [C2] only
    function test_F9_1_unbind_removes_from_dispatch() external {
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);

        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x11111111), 500_000);
        CallbackEndpoint memory c2 = CallbackEndpoint(1, address(0xCCC), bytes4(0x22222222), 500_000);
        bytes32 c1Id = setCallback(_cs(), c1);
        bytes32 c2Id = setCallback(_cs(), c2);

        validateBind(_os(), _cs(), o1Id, c1Id);
        immediateBind(_edt(), o1Id, c1Id);
        validateBind(_os(), _cs(), o1Id, c2Id);
        immediateBind(_edt(), o1Id, c2Id);

        // Unbind C1
        unbind(_edt(), o1Id, c1Id);

        // Dispatch should return only C2
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 1, "must return exactly 1 callback");
        assertEq(results[0], c2Id, "must return C2 only");
    }

    /// @dev F9.2 — Origin persists after last unbind.
    ///      Given: active binding (O1, C1) — only binding for O1
    ///      When:  unbind(O1, C1)
    ///      Then:  origin O1 still registered (getOriginExists returns true)
    ///      When:  dispatch(O1)
    ///      Then:  returns empty array
    function test_F9_2_origin_persists_after_last_unbind() external {
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);

        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x11111111), 500_000);
        bytes32 c1Id = setCallback(_cs(), c1);

        validateBind(_os(), _cs(), o1Id, c1Id);
        immediateBind(_edt(), o1Id, c1Id);

        // Unbind the only binding
        unbind(_edt(), o1Id, c1Id);

        // Origin must still be registered
        assertTrue(getOriginExists(_os(), o1Id), "origin must still exist after last unbind");

        // Dispatch must return empty array
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 0, "dispatch must return empty array after last unbind");
    }

    /// @dev F9.3 — Re-bind after unbind.
    ///      Given: unbound (O1, C1)
    ///      When:  immediateBind(O1, C1) again
    ///      Then:  new binding created, Active state
    ///      When:  dispatch(O1)
    ///      Then:  returns [C1]
    function test_F9_3_rebind_after_unbind() external {
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);

        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x11111111), 500_000);
        bytes32 c1Id = setCallback(_cs(), c1);

        validateBind(_os(), _cs(), o1Id, c1Id);
        immediateBind(_edt(), o1Id, c1Id);

        // Unbind
        unbind(_edt(), o1Id, c1Id);

        // Re-bind
        bytes32 bId = immediateBind(_edt(), o1Id, c1Id);

        // Verify new binding is Active
        Binding storage b = getBinding(_edt(), bId);
        assertEq(uint8(b.state), uint8(BindingState.Active), "re-bound state must be Active");

        // Dispatch must return C1
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 1, "must return exactly 1 callback after re-bind");
        assertEq(results[0], c1Id, "must return C1 after re-bind");
    }

    /// @dev F9.4 — Unbind non-existent binding reverts.
    ///      Given: no binding for (O1, C3)
    ///      When:  unbind(O1, C3)
    ///      Then:  reverts with BindingNotFound
    function test_F9_4_unbind_nonexistent_reverts() external {
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);

        CallbackEndpoint memory c3 = CallbackEndpoint(1, address(0xEEE), bytes4(0x33333333), 500_000);
        bytes32 c3Id = setCallback(_cs(), c3);

        bytes32 expectedBId = bindingId(o1Id, c3Id);

        vm.expectRevert(abi.encodeWithSelector(BindingNotFound.selector, expectedBId));
        this.externalUnbind(o1Id, c3Id);
    }

    /// @dev External wrapper for unbind so vm.expectRevert works with free functions.
    function externalUnbind(bytes32 _originId, bytes32 _callbackId) external {
        unbind(_edt(), _originId, _callbackId);
    }

    /// @dev F9.5 — Unbind preserves other bindings in fan-out.
    ///      Given: bindings (O1, C1), (O1, C2), (O1, C3)
    ///      When:  unbind(O1, C2) — remove middle
    ///      When:  dispatch(O1)
    ///      Then:  returns [C1, C3] — order preserved, middle removed
    function test_F9_5_unbind_preserves_other_bindings_fan_out() external {
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);

        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x11111111), 500_000);
        CallbackEndpoint memory c2 = CallbackEndpoint(1, address(0xCCC), bytes4(0x22222222), 500_000);
        CallbackEndpoint memory c3 = CallbackEndpoint(1, address(0xDDD), bytes4(0x33333333), 500_000);
        bytes32 c1Id = setCallback(_cs(), c1);
        bytes32 c2Id = setCallback(_cs(), c2);
        bytes32 c3Id = setCallback(_cs(), c3);

        validateBind(_os(), _cs(), o1Id, c1Id);
        immediateBind(_edt(), o1Id, c1Id);
        validateBind(_os(), _cs(), o1Id, c2Id);
        immediateBind(_edt(), o1Id, c2Id);
        validateBind(_os(), _cs(), o1Id, c3Id);
        immediateBind(_edt(), o1Id, c3Id);

        // Unbind middle (C2)
        unbind(_edt(), o1Id, c2Id);

        // Dispatch must return [C1, C3] in order
        bytes32[] memory results = dispatch(_edt(), o1Id);
        assertEq(results.length, 2, "must return exactly 2 callbacks");
        assertEq(results[0], c1Id, "first must be C1");
        assertEq(results[1], c3Id, "second must be C3");
    }

    /// @dev F9.6 — Binding count decrements on unbind.
    ///      Given: 3 bindings total
    ///      When:  unbind one
    ///      Then:  getBindingTotalCount == 2
    ///      Then:  getBindingCountByOrigin == 2
    function test_F9_6_binding_count_decrements_on_unbind() external {
        OriginEndpoint memory o1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        bytes32 o1Id = setOrigin(_os(), o1);

        CallbackEndpoint memory c1 = CallbackEndpoint(1, address(0xBBB), bytes4(0x11111111), 500_000);
        CallbackEndpoint memory c2 = CallbackEndpoint(1, address(0xCCC), bytes4(0x22222222), 500_000);
        CallbackEndpoint memory c3 = CallbackEndpoint(1, address(0xDDD), bytes4(0x33333333), 500_000);
        bytes32 c1Id = setCallback(_cs(), c1);
        bytes32 c2Id = setCallback(_cs(), c2);
        bytes32 c3Id = setCallback(_cs(), c3);

        validateBind(_os(), _cs(), o1Id, c1Id);
        immediateBind(_edt(), o1Id, c1Id);
        validateBind(_os(), _cs(), o1Id, c2Id);
        immediateBind(_edt(), o1Id, c2Id);
        validateBind(_os(), _cs(), o1Id, c3Id);
        immediateBind(_edt(), o1Id, c3Id);

        assertEq(getBindingTotalCount(_edt()), 3, "total count must be 3 before unbind");
        assertEq(getBindingCountByOrigin(_edt(), o1Id), 3, "origin count must be 3 before unbind");

        // Unbind one
        unbind(_edt(), o1Id, c2Id);

        assertEq(getBindingTotalCount(_edt()), 2, "total count must be 2 after unbind");
        assertEq(getBindingCountByOrigin(_edt(), o1Id), 2, "origin count must be 2 after unbind");
    }
}
