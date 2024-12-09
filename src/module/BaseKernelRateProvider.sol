// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";

import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

abstract contract BaseKernelRateProvider is IProvider {
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

    function getRate(address asset) public view virtual returns (uint256);
}
