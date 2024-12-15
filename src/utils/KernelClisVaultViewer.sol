// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, Math} from "lib/yieldnest-vault/src/Common.sol";

import {IKernelProvider} from "src/interface/IKernelProvider.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";

import {KernelVaultViewer} from "src/utils/KernelVaultViewer.sol";

contract KernelClisVaultViewer is KernelVaultViewer {
    function _maxWithdrawAsset(address asset_, address owner) internal view override returns (uint256 maxAssets) {
        if (!vault().getAsset(asset_).active) {
            return 0;
        }

        (maxAssets,) = _convertToAssets(asset_, vault().balanceOf(owner), Math.Rounding.Floor);

        uint256 availableAssets = IERC20(asset_).balanceOf(address(vault()));

        if (vault().getSyncWithdraw() && asset_ == vault().asset()) {
            address clisbnb = IKernelConfig(IStakerGateway(vault().getStakerGateway()).getConfig()).getClisBnbAddress();
            address kernelVault = IStakerGateway(vault().getStakerGateway()).getVault(clisbnb);
            uint256 availableAssetsInKernel = IERC20(kernelVault).balanceOf(address(vault()));
            availableAssets += availableAssetsInKernel;
        }

        if (availableAssets < maxAssets) {
            maxAssets = availableAssets;
        }
    }

    /**
     * @notice Internal function to get the underlying asset if the asset itself is a kernel vault
     * @param asset_ The address of the asset.
     * @return address The underlying asset
     * @dev This function must NOT revert
     */
    function _getUnderlyingAsset(address asset_) internal view override returns (address) {
        address clisbnb = IKernelConfig(IStakerGateway(vault().getStakerGateway()).getConfig()).getClisBnbAddress();
        IKernelProvider provider = IKernelProvider(vault().provider());
        try provider.tryGetVaultAsset(asset_) returns (address underlyingAsset) {
            if (underlyingAsset == clisbnb) {
                return vault().asset();
            }
            return underlyingAsset;
        } catch {
            return address(0);
        }
    }
}
