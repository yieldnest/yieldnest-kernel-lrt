// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

import {ISlisBnbStakeManager} from "lib/yieldnest-vault/src/interface/external/lista/ISlisBnbStakeManager.sol";
import {IBNBXStakeManagerV2} from "lib/yieldnest-vault/src/interface/external/stader/IBNBXStakeManagerV2.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

import {BaseKernelRateProvider} from "./BaseKernelRateProvider.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

contract BTCRateProvider is BaseKernelRateProvider {
    function getRate(address asset) public view override returns (uint256) {
        if (asset == MC.BTCB) {
            return 1e18;
        }

        if (asset == MC.SOLVBTC) {
            return 1e18;
        }

        if (asset == MC.SOLVBTC_BNN) {
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
