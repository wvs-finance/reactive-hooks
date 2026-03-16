// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {CallbackEndpoint} from "../types/CallbackEndpoint.sol";
import {DLL, pushBack, contains, size, head, isEmpty} from "../libraries/DoublyLinkedListLib.sol";

/// @dev Dual-representation storage for callback endpoints.
///      Hash-indexed for O(1) lookup (INV-006 round-trip).
///      Chain-indexed for enumeration (INV-008 no phantoms).
struct CallbackRegistryStorage {
    /// @dev callbackId => CallbackEndpoint struct. O(1) lookup by hash.
    mapping(bytes32 => CallbackEndpoint) callbacks;
    /// @dev callbackId => existence flag. Dedup guard (INV-004 idempotent).
    mapping(bytes32 => bool) exists;
    /// @dev chainId => doubly-linked list of callbackIds. O(1) insert/remove, FIFO order.
    mapping(uint32 => DLL) callbacksByChain;
    /// @dev Total registered callback count across all chains (INV-007 consistency).
    uint256 totalCount;
}

/// @dev Namespaced storage slot for CallbackRegistryStorage.
///      Following existing Compose/Mod pattern (keccak256 slot isolation).
function _callbackRegistryStorage() pure returns (CallbackRegistryStorage storage s) {
    bytes32 slot = keccak256("reactive-hooks.storage.CallbackRegistry");
    assembly {
        s.slot := slot
    }
}

// --- Setters ---

/// @dev Register a callback. Idempotent (INV-004). Updates both representations (INV-008).
function setCallback(CallbackRegistryStorage storage s, CallbackEndpoint memory endpoint) returns (bytes32 id) {
    id = endpoint.callbackId();
    if (s.exists[id]) return id;

    s.callbacks[id] = endpoint;
    s.exists[id] = true;
    pushBack(s.callbacksByChain[endpoint.chainId], id);
    s.totalCount++;
}

// --- Getters ---

/// @dev Check if a callback is registered.
function getCallbackExists(CallbackRegistryStorage storage s, bytes32 id) view returns (bool) {
    return s.exists[id];
}

/// @dev Lookup callback by hash. Caller must check exists first (INV-006 round-trip).
function getCallback(CallbackRegistryStorage storage s, bytes32 id) view returns (CallbackEndpoint storage) {
    return s.callbacks[id];
}

/// @dev Get count of callbacks registered on a specific chain.
function getCallbackCountByChain(CallbackRegistryStorage storage s, uint32 chainId) view returns (uint256) {
    return size(s.callbacksByChain[chainId]);
}

/// @dev Get the first callbackId in the chain's list, or bytes32(0) if empty.
function getCallbackHeadByChain(CallbackRegistryStorage storage s, uint32 chainId) view returns (bytes32) {
    return head(s.callbacksByChain[chainId]);
}

/// @dev Check if a chain has any registered callbacks.
function isChainEmptyCallbacks(CallbackRegistryStorage storage s, uint32 chainId) view returns (bool) {
    return isEmpty(s.callbacksByChain[chainId]);
}

/// @dev Check if a specific callbackId is in a chain's list.
function isCallbackInChain(CallbackRegistryStorage storage s, uint32 chainId, bytes32 id) view returns (bool) {
    return contains(s.callbacksByChain[chainId], id);
}

/// @dev Get total registered callback count across all chains (INV-007).
function getCallbackTotalCount(CallbackRegistryStorage storage s) view returns (uint256) {
    return s.totalCount;
}
