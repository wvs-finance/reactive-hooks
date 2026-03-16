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
    getBinding,
    getBindingCountByOrigin
} from "../modules/EventDispatchStorageMod.sol";

import {isSelfSync} from "./SelfSyncLib.sol";
import {DLL, SENTINEL, NEXT} from "./DoublyLinkedListLib.sol";

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

// ──────────────────────────────────────────────
// Quote-Then-Fund (F10)
// Per reactive-smart-contracts skill: On Reactive Network, if you send ETH
// to SystemContract (0x...fffFfF) as part of a transaction that later reverts,
// the ETH is NOT refunded. So we quote first, verify balance, then fund
// ONLY after all checks pass.
// ──────────────────────────────────────────────

/// @dev Estimated subscription cost for a new origin.
///      In production, this would query SystemContract for current pricing.
uint256 constant SUBSCRIPTION_COST_ESTIMATE = 0.01 ether;

/// @dev Quote the cost of binding. Returns 0 if origin already has active subscriptions.
///      This is a VIEW function — no state changes, no ETH movement.
///      The caller uses this to check balance BEFORE calling immediateBind().
///
///      Per reactive-smart-contracts skill: SystemContract keeps ETH on revert,
///      so we quote first, verify balance, then fund ONLY after all checks pass.
function quoteBind(
    EventDispatchStorage storage edt,
    OriginRegistryStorage storage /* origins */,
    bytes32 _originId
) view returns (uint256 cost) {
    // If origin already has active bindings, no new subscription needed
    // (origin lifecycle is independent — design decision Q8-B)
    if (getBindingCountByOrigin(edt, _originId) > 0) {
        return 0;
    }
    // First binding for this origin: subscription cost applies
    // Actual cost depends on Reactive Network pricing — use a constant estimate
    // In production, this would query SystemContract for current pricing
    return SUBSCRIPTION_COST_ESTIMATE;
}

/// @dev Full funded bind: validate -> quote -> check balance -> bind.
///      Reverts before any ETH transfer if validation or balance check fails.
///      Caller must still handle the actual depositToSystem() call AFTER this returns.
///
///      Phase 1: Validate (quote) — all checks, no state changes
///      Phase 2: Bind — state change ONLY after all validation passes
///      Phase 3: Funding — caller handles depositToSystem() with `cost` amount
///      We do NOT send ETH here because this is a free function.
///      The reactive contract calls depositToSystem(address(this)) after this returns.
function fundedBind(
    EventDispatchStorage storage edt,
    OriginRegistryStorage storage origins,
    CallbackRegistryStorage storage callbacks,
    bytes32 _originId,
    bytes32 _callbackId,
    uint256 availableBalance
) returns (bytes32 id, uint256 cost) {
    // Phase 1: Validate (quote) — all checks, no state changes
    validateBind(origins, callbacks, _originId, _callbackId);
    cost = quoteBind(edt, origins, _originId);

    if (cost > availableBalance) {
        revert InsufficientFunds(cost, availableBalance);
    }

    // Phase 2: Bind — state change ONLY after all validation passes
    id = immediateBind(edt, _originId, _callbackId);

    // Phase 3: Funding — caller handles depositToSystem() with `cost` amount
    // We do NOT send ETH here because this is a free function.
    // The reactive contract calls depositToSystem(address(this)) after this returns.
}

// ──────────────────────────────────────────────
// Dispatch — fan-out from origin to active callbacks
// This is the hot path — called by ReactVM's react() for every matching event.
// Walks the DLL of bindings for the origin, collecting only Active callbacks.
// Paused and PendingFunding bindings are skipped.
// ──────────────────────────────────────────────

/// @dev Dispatch: given an originId, return all Active callbackIds in FIFO order.
///      Two-pass: count first, then collect (avoids dynamic array resizing).
function dispatch(
    EventDispatchStorage storage edt,
    bytes32 _originId
) view returns (bytes32[] memory activeCallbacks) {
    DLL storage list = edt.bindingsByOrigin[_originId];

    // First pass: count active bindings
    uint256 count = 0;
    bytes32 current = list.nodes[SENTINEL][NEXT];
    while (current != SENTINEL) {
        if (edt.bindings[current].state == BindingState.Active) {
            count++;
        }
        current = list.nodes[current][NEXT];
    }

    // Second pass: collect active callback IDs
    activeCallbacks = new bytes32[](count);
    uint256 idx = 0;
    current = list.nodes[SENTINEL][NEXT];
    while (current != SENTINEL) {
        Binding storage b = edt.bindings[current];
        if (b.state == BindingState.Active) {
            activeCallbacks[idx] = b.callbackId;
            idx++;
        }
        current = list.nodes[current][NEXT];
    }
}
