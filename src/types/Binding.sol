// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @dev State of a binding in the Event Dispatch Table.
enum BindingState {
    /// @dev Not yet funded. Created by scheduleBind(). Waiting for auto-activate via self-sync.
    PendingFunding,
    /// @dev Fully active. Subscription is live, callbacks will be dispatched.
    Active,
    /// @dev Manually paused. Subscription remains active but dispatch skips this binding.
    Paused
}

/// @dev A binding connects an origin event to a callback destination in the EDT.
struct Binding {
    bytes32 originId;
    bytes32 callbackId;
    BindingState state;
}

/// @dev Deterministic binding identity. A binding is uniquely identified by its origin+callback pair.
function bindingId(bytes32 _originId, bytes32 _callbackId) pure returns (bytes32) {
    return keccak256(abi.encodePacked(_originId, _callbackId));
}

error OriginNotRegistered(bytes32 originId);
error CallbackNotRegistered(bytes32 callbackId);
error BindingNotFound(bytes32 bindingId);
error InsufficientFunds(uint256 required, uint256 available);
