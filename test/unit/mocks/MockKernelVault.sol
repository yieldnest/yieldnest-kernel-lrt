// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";

contract MockKernelVault {
    address private _asset;

    mapping(address => uint256) private _balanceOf;

    constructor(address asset) {
        _asset = asset;
        IERC20(asset).approve(msg.sender, type(uint256).max);
    }

    function getAsset() external view returns (address) {
        return _asset;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balanceOf[owner];
    }

    function mint(address owner, uint256 amount) external {
        _balanceOf[owner] += amount;
    }

    function burn(address owner, uint256 amount) external {
        _balanceOf[owner] -= amount;
    }
}
