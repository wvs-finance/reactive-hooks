// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {requireRN, requireVM, OnlyReactRN, OnlyReactVM} from "../modules/ReactVMMod.sol";
import {ISubscriptionService} from "reactive-lib/interfaces/ISubscriptionService.sol";

uint256 constant LASNA_CHAIN_ID = 5318007;
uint256 constant REACTIVE_MAINNET_CHAIN_ID = 1597;
uint256 constant REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

error OnlyReactiveNetwork();

function onlyRN() view {
    require(block.chainid == LASNA_CHAIN_ID || block.chainid == REACTIVE_MAINNET_CHAIN_ID, OnlyReactiveNetwork());
}

// ──────────────────────────────────────────────
// Reactive Network (RN) instance subscriptions
// ──────────────────────────────────────────────
// requireRN: extcodesize guard — confirms NOT in ReactVM instance
// onlyRN:    chainid guard    — confirms chain IS Reactive Network

function reactiveNetworkSingleSubscription(ISubscriptionService self, address sub, uint256 sig) {
    requireRN();
    onlyRN();
    self.subscribe(block.chainid, sub, sig, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
}

function reactiveNetworkBatchSubscription(ISubscriptionService self, address sub, uint256[] memory sigs) {
    requireRN();
    onlyRN();
    for (uint256 i; i < sigs.length; ++i) {
        self.subscribe(block.chainid, sub, sigs[i], REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }
}

function reactiveNetworkSingleUnsubscription(ISubscriptionService self, address sub, uint256 sig) {
    requireRN();
    onlyRN();
    self.unsubscribe(block.chainid, sub, sig, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
}

function reactiveNetworkBatchUnsubscription(ISubscriptionService self, address sub, uint256[] memory sigs) {
    requireRN();
    onlyRN();
    for (uint256 i; i < sigs.length; ++i) {
        self.unsubscribe(block.chainid, sub, sigs[i], REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }
}

// ──────────────────────────────────────────────
// ReactVM instance subscriptions
// ──────────────────────────────────────────────
// requireVM: extcodesize guard — confirms IN ReactVM instance
// ReactVM subscribes to external chains, so chainId is a parameter.
// Deposits go through the SystemContract to fund the subscription.

function reactVMSingleSubscription(ISubscriptionService self, uint256 chainId, address sub, uint256 sig) {
    requireVM();
    self.subscribe(chainId, sub, sig, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
}

function reactVMBatchSubscription(ISubscriptionService self, uint256 chainId, address sub, uint256[] memory sigs) {
    requireVM();
    for (uint256 i; i < sigs.length; ++i) {
        self.subscribe(chainId, sub, sigs[i], REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }
}

function reactVMSingleUnsubscription(ISubscriptionService self, uint256 chainId, address sub, uint256 sig) {
    requireVM();
    self.unsubscribe(chainId, sub, sig, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
}

function reactVMBatchUnsubscription(ISubscriptionService self, uint256 chainId, address sub, uint256[] memory sigs) {
    requireVM();
    for (uint256 i; i < sigs.length; ++i) {
        self.unsubscribe(chainId, sub, sigs[i], REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }
}
