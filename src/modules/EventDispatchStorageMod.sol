// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Binding, BindingState, bindingId} from "../types/Binding.sol";
import {DLL, pushBack, contains, size, head, isEmpty, remove} from "../libraries/DoublyLinkedListLib.sol";
import {BindingNotFound} from "../types/Binding.sol";

/// @dev Event Dispatch Table storage. Maps origins to callbacks via bindings.
///      The EDT is the core routing structure for the reactive subscription system.
struct EventDispatchStorage {
    /// @dev bindingId => Binding struct. O(1) lookup.
    mapping(bytes32 => Binding) bindings;
    /// @dev bindingId => existence flag. Dedup guard.
    mapping(bytes32 => bool) exists;
    /// @dev originId => DLL of bindingIds. Fan-out: one origin dispatches to many callbacks.
    ///      FIFO ordering preserved by DLL for deterministic dispatch order.
    mapping(bytes32 => DLL) bindingsByOrigin;
    /// @dev Total binding count across all origins.
    uint256 totalCount;
}

/// @dev Namespaced storage slot for EventDispatchStorage.
function _eventDispatchStorage() pure returns (EventDispatchStorage storage s) {
    bytes32 slot = keccak256("reactive-hooks.storage.EventDispatch");
    assembly {
        s.slot := slot
    }
}

// --- Setters ---

/// @dev Create a binding. Idempotent — returns existing bindingId if already bound.
///      Caller is responsible for validation (origin/callback exist) and funding.
///      This function ONLY manages the binding table, NOT subscriptions.
function setBinding(
    EventDispatchStorage storage s,
    bytes32 _originId,
    bytes32 _callbackId,
    BindingState initialState
) returns (bytes32 id) {
    id = bindingId(_originId, _callbackId);
    if (s.exists[id]) return id;

    s.bindings[id] = Binding(_originId, _callbackId, initialState);
    s.exists[id] = true;
    pushBack(s.bindingsByOrigin[_originId], id);
    s.totalCount++;
}

/// @dev Update a binding's state. Caller must verify binding exists.
function setBindingState(EventDispatchStorage storage s, bytes32 id, BindingState newState) {
    s.bindings[id].state = newState;
}

/// @dev Remove a binding from the EDT. Removes from DLL and clears storage.
function removeBinding(EventDispatchStorage storage s, bytes32 _originId, bytes32 _bindingId) {
    if (!s.exists[_bindingId]) revert BindingNotFound(_bindingId);

    remove(s.bindingsByOrigin[_originId], _bindingId);
    delete s.bindings[_bindingId];
    s.exists[_bindingId] = false;
    s.totalCount--;
}

// --- Getters ---

/// @dev Check if a binding exists.
function getBindingExists(EventDispatchStorage storage s, bytes32 id) view returns (bool) {
    return s.exists[id];
}

/// @dev Lookup binding by ID.
function getBinding(EventDispatchStorage storage s, bytes32 id) view returns (Binding storage) {
    return s.bindings[id];
}

/// @dev Get the number of bindings for an origin (fan-out count).
function getBindingCountByOrigin(EventDispatchStorage storage s, bytes32 _originId) view returns (uint256) {
    return size(s.bindingsByOrigin[_originId]);
}

/// @dev Get the first binding for an origin (head of fan-out list).
function getBindingHeadByOrigin(EventDispatchStorage storage s, bytes32 _originId) view returns (bytes32) {
    return head(s.bindingsByOrigin[_originId]);
}

/// @dev Check if a binding is in an origin's fan-out list.
function isBindingInOrigin(EventDispatchStorage storage s, bytes32 _originId, bytes32 _bindingId) view returns (bool) {
    return contains(s.bindingsByOrigin[_originId], _bindingId);
}

/// @dev Get total binding count.
function getBindingTotalCount(EventDispatchStorage storage s) view returns (uint256) {
    return s.totalCount;
}
