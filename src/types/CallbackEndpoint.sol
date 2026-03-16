// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @dev A callback target on a specific chain.
struct CallbackEndpoint {
    uint32 chainId;
    address target;
    bytes4 selector;
    uint256 gasLimit;
}

using {callbackId, eq, neq} for CallbackEndpoint global;

/// @dev Deterministic identity hash. gasLimit is NOT part of the identity — same callback
///      with different gas limits is the same callback.
///      INV-001 (determinism), INV-002 (injectivity), INV-003 (no zero-image).
function callbackId(CallbackEndpoint memory self) pure returns (bytes32) {
    return keccak256(abi.encodePacked(self.chainId, self.target, self.selector));
}

/// @dev Structural equality (all 4 fields).
function eq(CallbackEndpoint memory a, CallbackEndpoint memory b) pure returns (bool) {
    return a.chainId == b.chainId && a.target == b.target && a.selector == b.selector && a.gasLimit == b.gasLimit;
}

/// @dev Structural inequality.
function neq(CallbackEndpoint memory a, CallbackEndpoint memory b) pure returns (bool) {
    return !eq(a, b);
}
