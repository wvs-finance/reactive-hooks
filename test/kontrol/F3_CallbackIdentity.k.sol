// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CallbackEndpoint, callbackId} from "../../src/types/CallbackEndpoint.sol";

/// @dev Kontrol formal verification proofs for CallbackEndpoint identity (INV-001, INV-002, INV-003).
contract F3_CallbackIdentityProof is Test {
    /// @dev INV-001: callbackId is deterministic — same inputs always produce same output.
    function test_prove_callbackId_deterministic(
        uint32 chainId,
        address target,
        bytes4 selector,
        uint256 gasLimit
    ) public pure {
        CallbackEndpoint memory a = CallbackEndpoint(chainId, target, selector, gasLimit);
        CallbackEndpoint memory b = CallbackEndpoint(chainId, target, selector, gasLimit);
        assert(a.callbackId() == b.callbackId());
    }

    /// @dev INV-002a: callbackId is injective over chainId.
    function test_prove_callbackId_injective_chainId(
        uint32 chainId1,
        uint32 chainId2,
        address target,
        bytes4 selector,
        uint256 gasLimit
    ) public pure {
        vm.assume(chainId1 != chainId2);
        CallbackEndpoint memory a = CallbackEndpoint(chainId1, target, selector, gasLimit);
        CallbackEndpoint memory b = CallbackEndpoint(chainId2, target, selector, gasLimit);
        assert(a.callbackId() != b.callbackId());
    }

    /// @dev INV-002b: callbackId is injective over target.
    function test_prove_callbackId_injective_target(
        uint32 chainId,
        address target1,
        address target2,
        bytes4 selector,
        uint256 gasLimit
    ) public pure {
        vm.assume(target1 != target2);
        CallbackEndpoint memory a = CallbackEndpoint(chainId, target1, selector, gasLimit);
        CallbackEndpoint memory b = CallbackEndpoint(chainId, target2, selector, gasLimit);
        assert(a.callbackId() != b.callbackId());
    }

    /// @dev INV-002c: callbackId is injective over selector.
    function test_prove_callbackId_injective_selector(
        uint32 chainId,
        address target,
        bytes4 selector1,
        bytes4 selector2,
        uint256 gasLimit
    ) public pure {
        vm.assume(selector1 != selector2);
        CallbackEndpoint memory a = CallbackEndpoint(chainId, target, selector1, gasLimit);
        CallbackEndpoint memory b = CallbackEndpoint(chainId, target, selector2, gasLimit);
        assert(a.callbackId() != b.callbackId());
    }

    /// @dev INV-003: callbackId has no zero-image — no valid CallbackEndpoint maps to bytes32(0).
    function test_prove_callbackId_no_zero_image(
        uint32 chainId,
        address target,
        bytes4 selector,
        uint256 gasLimit
    ) public pure {
        CallbackEndpoint memory e = CallbackEndpoint(chainId, target, selector, gasLimit);
        assert(e.callbackId() != bytes32(0));
    }
}
