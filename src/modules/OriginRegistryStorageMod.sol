// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {OriginEndpoint} from "../types/OriginEndpoint.sol";
import {DLL, pushBack, contains, size, head, isEmpty} from "../libraries/DoublyLinkedListLib.sol";

/// @dev Dual-representation storage for origin endpoints.
///      Hash-indexed for O(1) lookup (INV-006 round-trip).
///      Chain-indexed for enumeration (INV-008 no phantoms).
struct OriginRegistryStorage {
    /// @dev originId => OriginEndpoint struct. O(1) lookup by hash.
    mapping(bytes32 => OriginEndpoint) origins;
    /// @dev originId => existence flag. Dedup guard (INV-004 idempotent).
    mapping(bytes32 => bool) exists;
    /// @dev chainId => doubly-linked list of originIds. O(1) insert/remove, FIFO order.
    mapping(uint32 => DLL) originsByChain;
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
    pushBack(s.originsByChain[endpoint.chainId], id);
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
    return size(s.originsByChain[chainId]);
}

/// @dev Get the first originId in the chain's list, or bytes32(0) if empty.
function getOriginHeadByChain(OriginRegistryStorage storage s, uint32 chainId) view returns (bytes32) {
    return head(s.originsByChain[chainId]);
}

/// @dev Check if a chain has any registered origins.
function isChainEmpty(OriginRegistryStorage storage s, uint32 chainId) view returns (bool) {
    return isEmpty(s.originsByChain[chainId]);
}

/// @dev Check if a specific originId is in a chain's list.
function isOriginInChain(OriginRegistryStorage storage s, uint32 chainId, bytes32 id) view returns (bool) {
    return contains(s.originsByChain[chainId], id);
}

/// @dev Get total registered origin count across all chains (INV-007).
function getOriginTotalCount(OriginRegistryStorage storage s) view returns (uint256) {
    return s.totalCount;
}
