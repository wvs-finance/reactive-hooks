// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {OriginEndpoint} from "../types/OriginEndpoint.sol";

/// @dev Dual-representation storage for origin endpoints.
///      Hash-indexed for O(1) lookup (INV-006 round-trip).
///      Chain-indexed for enumeration (INV-008 no phantoms).
struct OriginRegistryStorage {
    /// @dev originId => OriginEndpoint struct. O(1) lookup by hash.
    mapping(bytes32 => OriginEndpoint) origins;
    /// @dev originId => existence flag. Dedup guard (INV-004 idempotent).
    mapping(bytes32 => bool) exists;
    /// @dev chainId => list of originIds. Enumeration by chain.
    ///      Container TBD — placeholder for doubly-linked list integration.
    mapping(uint32 => bytes32[]) originsByChain;
    /// @dev Total registered origin count across all chains (INV-007 consistency).
    uint256 totalCount;
}

/// @dev Namespaced storage slot for OriginRegistryStorage.
///      Following existing Compose/Mod pattern (keccak256 slot isolation).
function _originRegistryStorage() pure returns (OriginRegistryStorage storage s) {
    bytes32 slot = keccak256("reactive-hooks.storage.OriginRegistry");
    assembly {
        s.slot := slot
    }
}

// --- Setters ---

/// @dev Register an origin. Idempotent (INV-004). Updates both representations (INV-008).
function setOrigin(OriginRegistryStorage storage s, OriginEndpoint memory endpoint) returns (bytes32 id) {
    id = endpoint.originId();
    if (s.exists[id]) return id;

    s.origins[id] = endpoint;
    s.exists[id] = true;
    s.originsByChain[endpoint.chainId].push(id);
    s.totalCount++;
}

// --- Getters ---

/// @dev Check if an origin is registered.
function getOriginExists(OriginRegistryStorage storage s, bytes32 id) view returns (bool) {
    return s.exists[id];
}

/// @dev Lookup origin by hash. Caller must check exists first (INV-006 round-trip).
function getOrigin(OriginRegistryStorage storage s, bytes32 id) view returns (OriginEndpoint storage) {
    return s.origins[id];
}

/// @dev Get count of origins registered on a specific chain.
function getOriginCountByChain(OriginRegistryStorage storage s, uint32 chainId) view returns (uint256) {
    return s.originsByChain[chainId].length;
}

/// @dev Get originId at index for a specific chain. For enumeration.
function getOriginIdByChainAt(OriginRegistryStorage storage s, uint32 chainId, uint256 index) view returns (bytes32) {
    return s.originsByChain[chainId][index];
}

/// @dev Get total registered origin count across all chains (INV-007).
function getOriginTotalCount(OriginRegistryStorage storage s) view returns (uint256) {
    return s.totalCount;
}
