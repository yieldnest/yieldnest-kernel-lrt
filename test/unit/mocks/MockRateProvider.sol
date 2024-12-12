/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts as MC, TestnetContracts as TC} from "script/Contracts.sol";

import {BaseKernelRateProvider} from "src/module/BaseKernelRateProvider.sol";

contract MockRateProvider is BaseKernelRateProvider {
    mapping(address => uint256) public rates;

    function getStakerGateway() public pure override returns (address) {
        return MC.STAKER_GATEWAY;
    }

    function addRate(address asset, uint256 rate) public {
        rates[asset] = rate;
    }

    function getRate(address asset) public view override returns (uint256) {
        uint256 rate = rates[asset];
        if (rate != 0) {
            return rate;
        }

        // check if a kernel vault is added as an asset
        address vaultAsset = tryGetVaultAsset(asset);

        if (vaultAsset != address(0)) {
            return getRate(vaultAsset); // add a multiplier to the rate if kernel changes from 1:1
        }

        revert UnsupportedAsset(asset);
    }
}
