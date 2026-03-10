// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {requireRN, OnlyReactRN} from "../modules/ReactVMMod.sol";
import {ISubscriptionService} from "reactive-lib/interfaces/ISubscriptionService.sol";

uint256 constant LASNA_CHAIN_ID = 5318007;
uint256 constant REACTIVE_MAINNET_CHAIN_ID = 1597;
uint256 constant REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

function onlyRN() view {
    require(block.chainid == LASNA_CHAIN_ID || block.chainid == REACTIVE_MAINNET_CHAIN_ID, OnlyReactRN());
}

    
// requireRN: extcodesize guard — confirms NOT in ReactVM instance
// onlyRN: chainid guard — confirms chain IS Reactive Network (not a foreign chain with 0x...fffFfF deployed)
function reactiveNetworkSingleSubscription(ISubscriptionService self, address sub, uint256 sig) {
    requireRN();
    onlyRN();
    self.subscribe(block.chainid, sub, sig, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
}
