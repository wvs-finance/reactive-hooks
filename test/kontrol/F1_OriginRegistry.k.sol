// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OriginEndpoint, originId} from "../../src/types/OriginEndpoint.sol";
import {
    OriginRegistryStorage,
    _originRegistryStorage,
    setOrigin,
    getOriginExists,
    getOrigin,
    getOriginCountByChain,
    getOriginHeadByChain,
    isOriginInChain,
    getOriginTotalCount
} from "../../src/modules/OriginRegistryStorageMod.sol";

/// @dev Kontrol/fuzz proofs for OriginRegistryStorage invariants (INV-004 through INV-008).
contract F1_OriginRegistryProof is Test {
    function _store() internal pure returns (OriginRegistryStorage storage) {
        return _originRegistryStorage();
    }

    /// @dev INV-004: Registration is idempotent — registering same origin twice does not change state.
    function test_prove_registerOrigin_idempotent(
        uint32 chainId,
        address emitter,
        bytes32 eventSig
    ) public {
        OriginEndpoint memory e = OriginEndpoint(chainId, emitter, eventSig);
        OriginRegistryStorage storage s = _store();

        bytes32 id1 = setOrigin(s, e);
        uint256 countAfterFirst = s.totalCount;
        uint256 chainCountAfterFirst = getOriginCountByChain(s, chainId);

        bytes32 id2 = setOrigin(s, e);
        uint256 countAfterSecond = s.totalCount;
        uint256 chainCountAfterSecond = getOriginCountByChain(s, chainId);

        assertEq(id1, id2, "IDs must match");
        assertEq(countAfterFirst, countAfterSecond, "totalCount must not change");
        assertEq(chainCountAfterFirst, chainCountAfterSecond, "chainCount must not change");
    }

    /// @dev INV-005: New origin increments totalCount and chainCount by exactly 1.
    function test_prove_registerOrigin_increments_count(
        uint32 chainId,
        address emitter,
        bytes32 eventSig
    ) public {
        OriginRegistryStorage storage s = _store();
        OriginEndpoint memory e = OriginEndpoint(chainId, emitter, eventSig);

        uint256 totalBefore = getOriginTotalCount(s);
        uint256 chainBefore = getOriginCountByChain(s, chainId);

        setOrigin(s, e);

        assertEq(getOriginTotalCount(s), totalBefore + 1, "totalCount must increment by 1");
        assertEq(getOriginCountByChain(s, chainId), chainBefore + 1, "chainCount must increment by 1");
    }

    /// @dev INV-006: lookupOrigin(originId(e)) returns e for any registered origin.
    function test_prove_lookupOrigin_roundtrip(
        uint32 chainId,
        address emitter,
        bytes32 eventSig
    ) public {
        OriginRegistryStorage storage s = _store();
        OriginEndpoint memory e = OriginEndpoint(chainId, emitter, eventSig);

        bytes32 id = setOrigin(s, e);
        OriginEndpoint storage stored = getOrigin(s, id);

        assertEq(stored.chainId, chainId, "chainId must round-trip");
        assertEq(stored.emitter, emitter, "emitter must round-trip");
        assertEq(stored.eventSig, eventSig, "eventSig must round-trip");
    }

    /// @dev INV-007: Sum of per-chain counts equals totalCount after random registrations.
    function testFuzz_chain_count_consistency(
        uint32[5] memory chainIds,
        address[5] memory emitters,
        bytes32[5] memory eventSigs
    ) public {
        OriginRegistryStorage storage s = _store();
        uint32[] memory seenChains = new uint32[](5);
        uint256 seenCount = 0;

        for (uint256 i = 0; i < 5; i++) {
            OriginEndpoint memory e = OriginEndpoint(chainIds[i], emitters[i], eventSigs[i]);
            setOrigin(s, e);

            bool found = false;
            for (uint256 j = 0; j < seenCount; j++) {
                if (seenChains[j] == chainIds[i]) { found = true; break; }
            }
            if (!found) { seenChains[seenCount] = chainIds[i]; seenCount++; }
        }

        uint256 sum = 0;
        for (uint256 i = 0; i < seenCount; i++) {
            sum += getOriginCountByChain(s, seenChains[i]);
        }

        assertEq(sum, getOriginTotalCount(s), "sum of chain counts must equal totalCount");
    }

    /// @dev INV-008: Origin appears in chain list iff it exists in hash lookup (no phantoms).
    function test_prove_no_phantom_origins(
        uint32 chainId,
        address emitter,
        bytes32 eventSig
    ) public {
        OriginRegistryStorage storage s = _store();
        OriginEndpoint memory e = OriginEndpoint(chainId, emitter, eventSig);
        bytes32 id = e.originId();

        // Before registration: not in hash map, not in chain list
        assertFalse(getOriginExists(s, id), "must not exist before registration");
        assertFalse(isOriginInChain(s, chainId, id), "must not be in chain list before registration");

        // After registration: in hash map AND in chain list
        setOrigin(s, e);
        assertTrue(getOriginExists(s, id), "must exist after registration");
        assertTrue(isOriginInChain(s, chainId, id), "must be in chain list after registration");
        assertEq(getOriginCountByChain(s, chainId), 1, "chain count must be 1");
    }
}
