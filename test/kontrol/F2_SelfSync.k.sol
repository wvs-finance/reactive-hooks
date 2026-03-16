// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {isSelfSync} from "../../src/libraries/SelfSyncLib.sol";

contract F2_SelfSyncKontrolTest is Test {
    /// @dev isSelfSync returns true ONLY for the two known Reactive Network chain IDs.
    function test_prove_isSelfSync_complete(uint32 chainId) external pure {
        bool result = isSelfSync(chainId);
        bool expected = (chainId == 5318007 || chainId == 1597);
        assert(result == expected);
    }

    /// @dev LASNA is always self-sync.
    function test_prove_isSelfSync_lasna() external pure {
        assert(isSelfSync(5318007));
    }

    /// @dev REACTIVE_MAINNET is always self-sync.
    function test_prove_isSelfSync_reactive_mainnet() external pure {
        assert(isSelfSync(1597));
    }
}
