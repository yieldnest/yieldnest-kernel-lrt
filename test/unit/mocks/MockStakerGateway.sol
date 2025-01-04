// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {MockKernelVault} from "test/unit/mocks/MockKernelVault.sol";

contract MockStakerGateway {
    mapping(address => mapping(address => uint256)) private _balanceOf;

    mapping(address => address) private _vaults;

    constructor(address[] memory assets) {
        for (uint256 i = 0; i < assets.length; i++) {
            _vaults[assets[i]] = address(new MockKernelVault(assets[i]));
        }
    }

    function getVault(address asset) external view returns (address) {
        return _vaults[asset];
    }

    function balanceOf(address asset, address owner) external view returns (uint256) {
        return _balanceOf[asset][owner];
    }

    function stake(address asset, uint256 amount, string calldata) external {
        IERC20(asset).transferFrom(msg.sender, _vaults[asset], amount);
        _balanceOf[asset][msg.sender] += amount;
        MockKernelVault(_vaults[asset]).mint(msg.sender, amount);
    }

    function unstake(address asset, uint256 amount, string calldata) external {
        IERC20(asset).transferFrom(_vaults[asset], msg.sender, amount);
        _balanceOf[asset][msg.sender] -= amount;
        MockKernelVault(_vaults[asset]).burn(msg.sender, amount);
    }
}
