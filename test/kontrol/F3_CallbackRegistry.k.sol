// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CallbackEndpoint, callbackId} from "../../src/types/CallbackEndpoint.sol";
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
} from "../../src/modules/CallbackRegistryStorageMod.sol";

/// @dev Kontrol/fuzz proofs for CallbackRegistryStorage invariants (INV-004 through INV-008).
contract F3_CallbackRegistryProof is Test {
    function _store() internal pure returns (CallbackRegistryStorage storage) {
        return _callbackRegistryStorage();
    }

    /// @dev INV-004: Registration is idempotent — registering same callback twice does not change state.
    function test_prove_registerCallback_idempotent(
        uint32 chainId,
        address target,
        bytes4 selector,
        uint256 gasLimit
    ) public {
        CallbackEndpoint memory e = CallbackEndpoint(chainId, target, selector, gasLimit);
        CallbackRegistryStorage storage s = _store();

        bytes32 id1 = setCallback(s, e);
        uint256 countAfterFirst = s.totalCount;
        uint256 chainCountAfterFirst = getCallbackCountByChain(s, chainId);

        bytes32 id2 = setCallback(s, e);
        uint256 countAfterSecond = s.totalCount;
        uint256 chainCountAfterSecond = getCallbackCountByChain(s, chainId);

        assertEq(id1, id2, "IDs must match");
        assertEq(countAfterFirst, countAfterSecond, "totalCount must not change");
        assertEq(chainCountAfterFirst, chainCountAfterSecond, "chainCount must not change");
    }

    /// @dev INV-005: New callback increments totalCount and chainCount by exactly 1.
    function test_prove_registerCallback_increments_count(
        uint32 chainId,
        address target,
        bytes4 selector,
        uint256 gasLimit
    ) public {
        CallbackRegistryStorage storage s = _store();
        CallbackEndpoint memory e = CallbackEndpoint(chainId, target, selector, gasLimit);

        uint256 totalBefore = getCallbackTotalCount(s);
        uint256 chainBefore = getCallbackCountByChain(s, chainId);

        setCallback(s, e);

        assertEq(getCallbackTotalCount(s), totalBefore + 1, "totalCount must increment by 1");
        assertEq(getCallbackCountByChain(s, chainId), chainBefore + 1, "chainCount must increment by 1");
    }

    /// @dev INV-006: lookupCallback(callbackId(e)) returns e for any registered callback.
    function test_prove_lookupCallback_roundtrip(
        uint32 chainId,
        address target,
        bytes4 selector,
        uint256 gasLimit
    ) public {
        CallbackRegistryStorage storage s = _store();
        CallbackEndpoint memory e = CallbackEndpoint(chainId, target, selector, gasLimit);

        bytes32 id = setCallback(s, e);
        CallbackEndpoint storage stored = getCallback(s, id);

        assertEq(stored.chainId, chainId, "chainId must round-trip");
        assertEq(stored.target, target, "target must round-trip");
        assertEq(stored.selector, selector, "selector must round-trip");
        assertEq(stored.gasLimit, gasLimit, "gasLimit must round-trip");
    }

    /// @dev INV-007: Sum of per-chain counts equals totalCount after random registrations.
    function testFuzz_callback_chain_count_consistency(
        uint32[5] memory chainIds,
        address[5] memory targets,
        bytes4[5] memory selectors,
        uint256[5] memory gasLimits
    ) public {
        CallbackRegistryStorage storage s = _store();
        uint32[] memory seenChains = new uint32[](5);
        uint256 seenCount = 0;

        for (uint256 i = 0; i < 5; i++) {
            CallbackEndpoint memory e = CallbackEndpoint(chainIds[i], targets[i], selectors[i], gasLimits[i]);
            setCallback(s, e);

            bool found = false;
            for (uint256 j = 0; j < seenCount; j++) {
                if (seenChains[j] == chainIds[i]) { found = true; break; }
            }
            if (!found) { seenChains[seenCount] = chainIds[i]; seenCount++; }
        }

        uint256 sum = 0;
        for (uint256 i = 0; i < seenCount; i++) {
            sum += getCallbackCountByChain(s, seenChains[i]);
        }

        assertEq(sum, getCallbackTotalCount(s), "sum of chain counts must equal totalCount");
    }

    /// @dev INV-008: Callback appears in chain list iff it exists in hash lookup (no phantoms).
    function test_prove_no_phantom_callbacks(
        uint32 chainId,
        address target,
        bytes4 selector,
        uint256 gasLimit
    ) public {
        CallbackRegistryStorage storage s = _store();
        CallbackEndpoint memory e = CallbackEndpoint(chainId, target, selector, gasLimit);
        bytes32 id = e.callbackId();

        // Before registration: not in hash map, not in chain list
        assertFalse(getCallbackExists(s, id), "must not exist before registration");
        assertFalse(isCallbackInChain(s, chainId, id), "must not be in chain list before registration");

        // After registration: in hash map AND in chain list
        setCallback(s, e);
        assertTrue(getCallbackExists(s, id), "must exist after registration");
        assertTrue(isCallbackInChain(s, chainId, id), "must be in chain list after registration");
        assertEq(getCallbackCountByChain(s, chainId), 1, "chain count must be 1");
    }
}
