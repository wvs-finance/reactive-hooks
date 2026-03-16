// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CallbackEndpoint, callbackId} from "../src/types/CallbackEndpoint.sol";
import {
    CallbackRegistryStorage,
    _callbackRegistryStorage,
    setCallback,
    getCallbackExists,
    getCallback,
    getCallbackCountByChain,
    getCallbackHeadByChain,
    isCallbackInChain,
    getCallbackTotalCount
} from "../src/modules/CallbackRegistryStorageMod.sol";

/// @dev F3 integration tests (F3.1-F3.6) from refs/edt-flows.md.
contract F3_CallbackIdentityTest is Test {
    bytes4 constant ON_V3_SWAP = bytes4(keccak256("onV3Swap(bytes)"));
    bytes4 constant ON_V3_MINT = bytes4(keccak256("onV3Mint(bytes)"));

    function _store() internal pure returns (CallbackRegistryStorage storage) {
        return _callbackRegistryStorage();
    }

    /// @dev F3.1: callbackId produces identical results for identical inputs.
    function test_F3_1_determinism() public pure {
        CallbackEndpoint memory a = CallbackEndpoint(1, address(0xADA9fe8), bytes4(0x12345678), 500000);
        CallbackEndpoint memory b = CallbackEndpoint(1, address(0xADA9fe8), bytes4(0x12345678), 500000);
        assertEq(a.callbackId(), b.callbackId());
    }

    /// @dev F3.2: different selector produces different callbackId.
    function test_F3_2_injectivity_selector() public pure {
        CallbackEndpoint memory a = CallbackEndpoint(1, address(0xAAA), ON_V3_SWAP, 500000);
        CallbackEndpoint memory b = CallbackEndpoint(1, address(0xAAA), ON_V3_MINT, 500000);
        assertTrue(a.callbackId() != b.callbackId());
    }

    /// @dev F3.3: different target produces different callbackId.
    function test_F3_3_injectivity_target() public pure {
        CallbackEndpoint memory a = CallbackEndpoint(1, address(0xAAA), ON_V3_SWAP, 500000);
        CallbackEndpoint memory b = CallbackEndpoint(1, address(0xBBB), ON_V3_SWAP, 500000);
        assertTrue(a.callbackId() != b.callbackId());
    }

    /// @dev F3.4: different chainId produces different callbackId.
    function test_F3_4_injectivity_chainId() public pure {
        CallbackEndpoint memory a = CallbackEndpoint(1, address(0xAAA), ON_V3_SWAP, 500000);
        CallbackEndpoint memory b = CallbackEndpoint(42161, address(0xAAA), ON_V3_SWAP, 500000);
        assertTrue(a.callbackId() != b.callbackId());
    }

    /// @dev F3.5: register + lookup round-trip.
    function test_F3_5_register_lookup_roundtrip() public {
        CallbackRegistryStorage storage s = _store();

        CallbackEndpoint memory e = CallbackEndpoint(1, address(0xADA9fe8), ON_V3_SWAP, 500000);
        bytes32 id = setCallback(s, e);

        assertTrue(getCallbackExists(s, id));
        assertEq(getCallbackCountByChain(s, 1), 1);
        assertTrue(isCallbackInChain(s, 1, id));

        CallbackEndpoint storage stored = getCallback(s, id);
        assertEq(stored.chainId, 1);
        assertEq(stored.target, address(0xADA9fe8));
        assertEq(stored.selector, ON_V3_SWAP);
        assertEq(stored.gasLimit, 500000);
    }

    /// @dev F3.6: double registration produces no revert and no duplicate.
    function test_F3_6_idempotent_registration() public {
        CallbackRegistryStorage storage s = _store();
        CallbackEndpoint memory e = CallbackEndpoint(1, address(0xADA9fe8), ON_V3_SWAP, 500000);

        bytes32 id1 = setCallback(s, e);
        bytes32 id2 = setCallback(s, e);

        assertEq(id1, id2);
        assertEq(getCallbackCountByChain(s, 1), 1);
        assertEq(getCallbackTotalCount(s), 1);
    }
}
