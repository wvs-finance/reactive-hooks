// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OriginEndpoint, originId} from "../src/types/OriginEndpoint.sol";
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
} from "../src/modules/OriginRegistryStorageMod.sol";

/// @dev F1 integration tests (F1.1–F1.6) from refs/edt-flows.md.
contract F1_OriginIdentityTest is Test {
    bytes32 constant SWAP_SIG = keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");
    bytes32 constant MINT_SIG = keccak256("Mint(address,address,int24,int24,uint128,uint256,uint256)");

    function _store() internal pure returns (OriginRegistryStorage storage) {
        return _originRegistryStorage();
    }

    /// @dev F1.1: originId produces identical results for identical inputs.
    function test_F1_1_determinism() public pure {
        OriginEndpoint memory a = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        OriginEndpoint memory b = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        assertEq(a.originId(), b.originId());
    }

    /// @dev F1.2: different eventSig produces different originId.
    function test_F1_2_injectivity_eventSig() public pure {
        OriginEndpoint memory a = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        OriginEndpoint memory b = OriginEndpoint(1, address(0xAAA), MINT_SIG);
        assertTrue(a.originId() != b.originId());
    }

    /// @dev F1.3: different chainId produces different originId.
    function test_F1_3_injectivity_chainId() public pure {
        OriginEndpoint memory a = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        OriginEndpoint memory b = OriginEndpoint(42161, address(0xAAA), SWAP_SIG);
        assertTrue(a.originId() != b.originId());
    }

    /// @dev F1.4: different emitter produces different originId.
    function test_F1_4_injectivity_emitter() public pure {
        OriginEndpoint memory a = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        OriginEndpoint memory b = OriginEndpoint(1, address(0xBBB), SWAP_SIG);
        assertTrue(a.originId() != b.originId());
    }

    /// @dev F1.5: register multiple origins, verify enumeration by chain and round-trip lookup.
    function test_F1_5_register_enumerate() public {
        OriginRegistryStorage storage s = _store();

        OriginEndpoint memory e1 = OriginEndpoint(1, address(0xAAA), SWAP_SIG);
        OriginEndpoint memory e2 = OriginEndpoint(1, address(0xAAA), MINT_SIG);
        OriginEndpoint memory e3 = OriginEndpoint(42161, address(0xBBB), SWAP_SIG);

        setOrigin(s, e1);
        setOrigin(s, e2);
        setOrigin(s, e3);

        // Chain 1: 2 entries
        assertEq(getOriginCountByChain(s, 1), 2);
        // Chain 42161: 1 entry
        assertEq(getOriginCountByChain(s, 42161), 1);
        // Total: 3
        assertEq(getOriginTotalCount(s), 3);

        // Both origins are in chain 1's list
        assertTrue(isOriginInChain(s, 1, e1.originId()));
        assertTrue(isOriginInChain(s, 1, e2.originId()));
        // e3 is in chain 42161's list
        assertTrue(isOriginInChain(s, 42161, e3.originId()));
        // e3 is NOT in chain 1's list
        assertFalse(isOriginInChain(s, 1, e3.originId()));

        // Round-trip lookup
        OriginEndpoint storage stored = getOrigin(s, e1.originId());
        assertEq(stored.chainId, 1);
        assertEq(stored.emitter, address(0xAAA));
        assertEq(stored.eventSig, SWAP_SIG);
    }

    /// @dev F1.6: double registration produces no revert and no duplicate.
    function test_F1_6_idempotent_registration() public {
        OriginRegistryStorage storage s = _store();
        OriginEndpoint memory e = OriginEndpoint(1, address(0xAAA), SWAP_SIG);

        bytes32 id1 = setOrigin(s, e);
        bytes32 id2 = setOrigin(s, e);

        assertEq(id1, id2);
        assertEq(getOriginCountByChain(s, 1), 1);
        assertEq(getOriginTotalCount(s), 1);
    }
}
