// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

import {ISlisBnbStakeManager} from "lib/yieldnest-vault/src/interface/external/lista/ISlisBnbStakeManager.sol";
import {IBNBXStakeManagerV2} from "lib/yieldnest-vault/src/interface/external/stader/IBNBXStakeManagerV2.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

contract KernelRateProvider is IProvider {
    error UnsupportedAsset(address asset);

    function tryGetVaultAsset(address vault) public view returns (address) {
        try IKernelVault(vault).getAsset() returns (address asset) {
            if (IStakerGateway(MC.STAKER_GATEWAY).getVault(asset) != vault) {
                return address(0);
            }
            return asset;
        } catch {
            return address(0);
        }
    }

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

        // check if a kernel vault is added as an asset
        address vaultAsset = tryGetVaultAsset(asset);

        if (vaultAsset != address(0)) {
            return getRate(vaultAsset); // add a multiplier to the rate if kernel changes from 1:1
        }

        revert UnsupportedAsset(asset);
    }
}
