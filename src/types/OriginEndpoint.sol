// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @dev An event source on a specific chain.
struct OriginEndpoint {
    uint32 chainId;
    address emitter;
    bytes32 eventSig;
}

using {originId, eq, neq} for OriginEndpoint global;

/// @dev Deterministic identity hash. INV-001 (determinism), INV-002 (injectivity), INV-003 (no zero-image).
function originId(OriginEndpoint memory self) pure returns (bytes32) {
    return keccak256(abi.encodePacked(self.chainId, self.emitter, self.eventSig));
}

/// @dev Structural equality.
function eq(OriginEndpoint memory a, OriginEndpoint memory b) pure returns (bool) {
    return a.chainId == b.chainId && a.emitter == b.emitter && a.eventSig == b.eventSig;
}

/// @dev Structural inequality.
function neq(OriginEndpoint memory a, OriginEndpoint memory b) pure returns (bool) {
    return !eq(a, b);
}
