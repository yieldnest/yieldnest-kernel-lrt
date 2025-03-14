/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {TestnetContracts as TC} from "script/Contracts.sol";

import {BaseKernelRateProvider} from "src/module/BaseKernelRateProvider.sol";

contract TestnetBTCRateProvider is BaseKernelRateProvider {
    function getStakerGateway() public pure override returns (address) {
        return TC.STAKER_GATEWAY;
    }

    function getRate(address asset) public view override returns (uint256) {
        if (asset == TC.BTCB) {
            return 1e18;
        }

        if (asset == TC.SOLVBTC) {
            return 1e18;
        }

        if (asset == TC.SOLVBTC_BBN) {
            return 1e18;
        }

        // check if a kernel vault is added as an asset
        address vaultAsset = tryGetVaultAsset(asset);

        if (vaultAsset != address(0)) {
            return getRate(vaultAsset); // add a multiplier to the rate if kernel changes from 1:1
        }

        revert UnsupportedAsset(asset);
    }
}
