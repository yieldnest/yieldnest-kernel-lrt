/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";

import {BaseKernelRateProvider} from "./BaseKernelRateProvider.sol";
import {ISolvBTCYieldToken} from "src/interface/external/solv/ISolvBTCYieldToken.sol";

/**
 * @title BTCRateProvider
 * @author Yieldnest
 * @notice Provides the rate of BTC for the Yieldnest Kernel
 */
contract BTCRateProvider is BaseKernelRateProvider {
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
        if (asset == MC.BTCB) {
            return 1e18;
        }

        if (asset == MC.SOLVBTC) {
            return 1e18;
        }

        if (asset == MC.SOLVBTC_BBN) {
            return ISolvBTCYieldToken(MC.SOLVBTC_BBN).getValueByShares(1e18);
        }

        // check if a kernel vault is added as an asset
        address vaultAsset = tryGetVaultAsset(asset);

        if (vaultAsset != address(0)) {
            return getRate(vaultAsset); // add a multiplier to the rate if kernel changes from 1:1
        }

        revert UnsupportedAsset(asset);
    }
}
