/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ISlisBnbStakeManager} from "lib/yieldnest-vault/src/interface/external/lista/ISlisBnbStakeManager.sol";
import {IBNBXStakeManagerV2} from "lib/yieldnest-vault/src/interface/external/stader/IBNBXStakeManagerV2.sol";

import {IAsBnbMinter} from "lib/yieldnest-vault/src/interface/external/astherus/IAsBnbMinter.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

import {BaseKernelRateProvider} from "./BaseKernelRateProvider.sol";

/**
 * @title BNBRateProvider
 * @author Yieldnest
 * @notice Provides the rate of BNB for the Yieldnest Kernel
 */
contract BNBRateProvider is BaseKernelRateProvider {
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
        if (asset == MC.WBNB) {
            return 1e18;
        }

        if (asset == MC.BNBX) {
            return IBNBXStakeManagerV2(MC.BNBX_STAKE_MANAGER).convertBnbXToBnb(1e18);
        }

        if (asset == MC.SLISBNB) {
            return ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER).convertSnBnbToBnb(1e18);
        }

        if (asset == MC.CLISBNB) {
            return 1e18;
        }

        if (asset == MC.ASBNB) {
            return ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER).convertSnBnbToBnb(
                IAsBnbMinter(MC.AS_BNB_MINTER).convertToTokens(1e18)
            );
        }

        // check if a kernel vault is added as an asset
        address vaultAsset = tryGetVaultAsset(asset);

        if (vaultAsset != address(0)) {
            return getRate(vaultAsset); // add a multiplier to the rate if kernel changes from 1:1
        }

        revert UnsupportedAsset(asset);
    }
}
