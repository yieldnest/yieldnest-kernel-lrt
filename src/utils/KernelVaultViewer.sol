// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, Math} from "lib/yieldnest-vault/src/Common.sol";

import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";

import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {BaseVaultViewer} from "lib/yieldnest-vault/src/utils/BaseVaultViewer.sol";

contract KernelVaultViewer is BaseVaultViewer {
    using Math for uint256;

    function vault() public view returns (KernelStrategy) {
        return KernelStrategy(payable(address(_getStorage().vault)));
    }
    /**
     * @notice Returns the maximum amount of assets that can be withdrawn for a specific asset by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxAssets The maximum amount of assets.
     */

    function maxWithdrawAsset(address asset_, address owner) public view returns (uint256 maxAssets) {
        if (vault().paused()) {
            return 0;
        }

        return _maxWithdrawAsset(asset_, owner);
    }

    /**
     * @dev See {maxWithdrawAsset}.
     */
    function _maxWithdrawAsset(address asset_, address owner) internal view virtual returns (uint256 maxAssets) {
        if (!vault().getAsset(asset_).active) {
            return 0;
        }

        (maxAssets,) = _convertToAssets(asset_, vault().balanceOf(owner), Math.Rounding.Floor);

        uint256 availableAssets = IERC20(asset_).balanceOf(address(vault()));

        if (vault().getSyncWithdraw()) {
            address kernelVault = IStakerGateway(vault().getStakerGateway()).getVault(asset_);
            uint256 availableAssetsInKernel = IERC20(kernelVault).balanceOf(address(vault()));
            availableAssets += availableAssetsInKernel;
        }

        if (availableAssets < maxAssets) {
            maxAssets = availableAssets;
        }
    }

    /**
     * @notice Internal function to convert vault shares to the base asset.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to convert.
     * @param rounding The rounding direction.
     * @return (uint256 assets, uint256 baseAssets) The equivalent amount of assets.
     */
    function _convertToAssets(address asset_, uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256, uint256)
    {
        uint256 baseAssets = shares.mulDiv(vault().totalAssets() + 1, vault().totalSupply() + 10 ** 0, rounding);
        uint256 assets = _convertBaseToAsset(asset_, baseAssets);

        return (assets, baseAssets);
    }

    /**
     * @notice Internal function to convert base denominated amount to asset value.
     * @param asset_ The address of the asset.
     * @param assets The amount of the asset.
     * @return uint256 The equivalent amount of assets.
     */
    function _convertBaseToAsset(address asset_, uint256 assets) internal view virtual returns (uint256) {
        uint256 rate = IProvider(vault().provider()).getRate(asset_);
        return assets.mulDiv(10 ** (vault().getAsset(asset_).decimals), rate, Math.Rounding.Floor);
    }
}
