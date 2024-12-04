// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

contract MockKernelVault {
    address private _asset;

    constructor(address asset) public {
        asset = asset;
    }

    function getAsset() external view returns (address) {
        return _asset;
    }
}
