// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";

contract MockKernelVault {
    address private _asset;

    constructor(address asset) {
        _asset = asset;
        IERC20(asset).approve(msg.sender, type(uint256).max);
    }

    function getAsset() external view returns (address) {
        return _asset;
    }
}
