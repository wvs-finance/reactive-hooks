// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {OriginEndpoint} from "../types/OriginEndpoint.sol";
import {CallbackEndpoint} from "../types/CallbackEndpoint.sol";
import {Binding, BindingState, bindingId, OriginNotRegistered, CallbackNotRegistered, InsufficientFunds} from "../types/Binding.sol";

import {
    OriginRegistryStorage,
    getOriginExists
} from "../modules/OriginRegistryStorageMod.sol";

import {
    CallbackRegistryStorage,
    getCallbackExists
} from "../modules/CallbackRegistryStorageMod.sol";

import {
    EventDispatchStorage,
    setBinding,
    setBindingState,
    getBindingExists,
    getBinding
} from "../modules/EventDispatchStorageMod.sol";

import {isSelfSync} from "./SelfSyncLib.sol";

// ──────────────────────────────────────────────
// Validation — all checks happen BEFORE any state changes or funding
// This is the "quote" phase of quote-then-fund.
// Per reactive-smart-contracts skill: Reactive Network keeps ETH on revert,
// so we MUST validate before sending any funds to SystemContract.
// ──────────────────────────────────────────────

error AlreadyBound(bytes32 bindingId);

/// @dev Validate that origin and callback are registered. Reverts if either is missing.
///      Called BEFORE any funding or state changes (quote-then-fund pattern).
function validateBind(
    OriginRegistryStorage storage origins,
    CallbackRegistryStorage storage callbacks,
    bytes32 _originId,
    bytes32 _callbackId
) view {
    if (!getOriginExists(origins, _originId)) {
        revert OriginNotRegistered(_originId);
    }
    if (!getCallbackExists(callbacks, _callbackId)) {
        revert CallbackNotRegistered(_callbackId);
    }
}

// ──────────────────────────────────────────────
// Bind — creates the binding AFTER validation passes
// Subscription activation is NOT handled here.
// Per reactive-smart-contracts skill:
//   - Subscriptions happen via ISubscriptionService.subscribe()
//   - This requires SystemContract which can't be simulated in Foundry
//   - Subscription routing (self-sync vs cross-chain) uses isSelfSync()
//   - The caller (reactive contract) handles subscription after bind() returns
// ──────────────────────────────────────────────

/// @dev Immediate bind — creates an Active binding.
///      Caller must have already:
///      1. Called validateBind() to check origin/callback exist
///      2. Verified sufficient funds for subscription via quoteBind()
///      3. Will call subscribe() AFTER this function returns (on Reactive Network)
///      Returns the bindingId. Idempotent — returns existing if already bound.
function immediateBind(
    EventDispatchStorage storage edt,
    bytes32 _originId,
    bytes32 _callbackId
) returns (bytes32) {
    return setBinding(edt, _originId, _callbackId, BindingState.Active);
}

/// @dev Scheduled bind — creates a PendingFunding binding.
///      No subscription activated. No funding required.
///      Will be auto-activated via self-sync when funding arrives (F6).
function scheduledBind(
    EventDispatchStorage storage edt,
    bytes32 _originId,
    bytes32 _callbackId
) returns (bytes32) {
    return setBinding(edt, _originId, _callbackId, BindingState.PendingFunding);
}

/// @dev Pause a binding — dispatch will skip it but subscription stays active.
///      Origin lifecycle is independent (per design decision Q8-B).
function pauseBind(EventDispatchStorage storage edt, bytes32 _bindingId) {
    setBindingState(edt, _bindingId, BindingState.Paused);
}

/// @dev Resume a paused binding — re-includes in dispatch.
function resumeBind(EventDispatchStorage storage edt, bytes32 _bindingId) {
    setBindingState(edt, _bindingId, BindingState.Active);
}
