// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Derive position key from V3 event fields.
// Matches V3's internal position key: keccak256(owner, tickLower, tickUpper).
function v3PositionKey(address owner, int24 tickLower, int24 tickUpper) pure returns (bytes32) {
    return keccak256(abi.encodePacked(owner, tickLower, tickUpper));
}
