// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

uint32 constant LASNA_CHAIN_ID_U32 = 5318007;
uint32 constant REACTIVE_MAINNET_CHAIN_ID_U32 = 1597;

/// @dev Returns true if chainId is a Reactive Network chain (self-sync target).
function isSelfSync(uint32 chainId) pure returns (bool) {
    return chainId == LASNA_CHAIN_ID_U32 || chainId == REACTIVE_MAINNET_CHAIN_ID_U32;
}
