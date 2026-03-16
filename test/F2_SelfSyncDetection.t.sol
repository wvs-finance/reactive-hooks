// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {
    isSelfSync,
    LASNA_CHAIN_ID_U32,
    REACTIVE_MAINNET_CHAIN_ID_U32
} from "../src/libraries/SelfSyncLib.sol";

contract F2_SelfSyncDetectionTest is Test {
    /// @dev F2.1 — Self-sync detection (LASNA)
    function test_F2_1_isSelfSync_lasna() external pure {
        assertTrue(isSelfSync(LASNA_CHAIN_ID_U32));
        assertTrue(isSelfSync(5318007));
    }

    /// @dev F2.2 — Self-sync detection (REACTIVE_MAINNET)
    function test_F2_2_isSelfSync_reactiveMainnet() external pure {
        assertTrue(isSelfSync(REACTIVE_MAINNET_CHAIN_ID_U32));
        assertTrue(isSelfSync(1597));
    }

    /// @dev F2.3 — Cross-chain detection (Ethereum)
    function test_F2_3_crossChain_ethereum() external pure {
        assertFalse(isSelfSync(1));
    }

    /// @dev F2.4 — Cross-chain detection (Arbitrum)
    function test_F2_4_crossChain_arbitrum() external pure {
        assertFalse(isSelfSync(42161));
    }

    /// @dev F2.5 — Fuzz: only LASNA and REACTIVE_MAINNET return true
    function test_F2_5_fuzz_isSelfSync(uint32 chainId) external pure {
        bool result = isSelfSync(chainId);
        bool expected = (chainId == 5318007 || chainId == 1597);
        assertEq(result, expected);
    }
}
