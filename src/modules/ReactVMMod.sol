// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../types/ReactVM.sol";


struct ReactVMStorage {
    ReactVm reactVm;
}

bytes32 constant REACT_VM_STORAGE_SLOT = keccak256("reactive.reactVM");

error OnlyReactVM();
error OnlyReactRN();

function reactVmStorage() pure returns (ReactVMStorage storage $) {
    bytes32 slot = REACT_VM_STORAGE_SLOT;
    assembly ("memory-safe") {
        $.slot := slot
    }
}
function reactVM() view returns (ReactVm) {
    ReactVMStorage storage $ = reactVmStorage();
    return $.reactVm;
}

function requireVM() view {
    require(isActive(reactVM()), OnlyReactVM());
}

function requireRN() view {
    require(!isActive(reactVM()), OnlyReactRN());
}
