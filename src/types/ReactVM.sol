// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


type ReactVm is bool;

function isReactiveVm() view returns (ReactVm) {
    uint256 size;
    assembly { size := extcodesize(0x0000000000000000000000000000000000fffFfF) }
    return ReactVm.wrap(size > 0);
}

function isActive(ReactVm vm) pure returns (bool) {
    return ReactVm.unwrap(vm);
}
