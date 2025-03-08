/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";

import {BaseKernelRateProvider} from "./BaseKernelRateProvider.sol";

/**
 * @title BitFiBTCRateProvider
 * @author Yieldnest
 * @notice Provides the rate of BTC for the Yieldnest Kernel
 */
contract BitFiBTCRateProvider is BaseKernelRateProvider {
    /**
     * @notice Returns the staker gateway address
     * @return The staker gateway address
     */
    function getStakerGateway() public pure override returns (address) {
        return MC.STAKER_GATEWAY;
    }

    /**
     * @notice Returns the rate of the given asset
     * @param asset The asset to get the rate for
     * @return The rate of the asset
     */
    function getRate(address asset) public view override returns (uint256) {
        if (asset == MC.BFBTC) {
            // BFBTC is a vault with BTCB as the underlying asset.
            // BFBTC is the only asset in this vault so we can just return 1e8
            // since BFBTC has 8 decimals
            return 1e8;
        }

        // check if a kernel vault is added as an asset
        address vaultAsset = tryGetVaultAsset(asset);

        if (vaultAsset != address(0)) {
            return getRate(vaultAsset); // add a multiplier to the rate if kernel changes from 1:1
        }

        revert UnsupportedAsset(asset);
    }
}
