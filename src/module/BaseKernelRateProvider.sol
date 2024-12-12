// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

abstract contract BaseKernelRateProvider is IProvider {
    error UnsupportedAsset(address asset);

    function getStakerGateway() public view virtual returns (address);

    function tryGetVaultAsset(address vault) internal view returns (address) {
        try IKernelVault(vault).getAsset() returns (address asset) {
            if (IStakerGateway(getStakerGateway()).getVault(asset) != vault) {
                return address(0);
            }
            return asset;
        } catch {
            return address(0);
        }
    }

    function getRate(address asset) public view virtual returns (uint256);
}
