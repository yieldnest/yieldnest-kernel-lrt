// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20Metadata, Math} from "lib/yieldnest-vault/src/Common.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {IKernelProvider} from "src/interface/IKernelProvider.sol";

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

        uint256 availableAssets = IERC20Metadata(asset_).balanceOf(address(vault()));

        if (vault().getSyncWithdraw()) {
            address kernelVault = IStakerGateway(vault().getStakerGateway()).getVault(asset_);
            uint256 availableAssetsInKernel = IERC20Metadata(kernelVault).balanceOf(address(vault()));
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
        uint256 rate = IKernelProvider(vault().provider()).getRate(asset_);
        return assets.mulDiv(10 ** (vault().getAsset(asset_).decimals), rate, Math.Rounding.Floor);
    }

    function findIndex(address[] memory assets, address asset) internal pure returns (int256) {
        for (uint256 i = 0; i < assets.length; ++i) {
            if (assets[i] == asset) {
                return int256(i);
            }
        }
        return -1;
    }

    /**
     * @notice Internal function to get the underlying asset if the asset itself is a kernel vault
     * @param asset_ The address of the asset.
     * @return address The underlying asset
     * @dev This function must NOT revert
     */
    function _getUnderlyingAsset(address asset_) internal view virtual returns (address) {
        IKernelProvider provider = IKernelProvider(vault().provider());
        try provider.tryGetVaultAsset(asset_) returns (address underlyingAsset) {
            return underlyingAsset;
        } catch {
            return address(0);
        }
    }

    /**
     * @notice Retrieves information about all underlying assets in the system
     * @return assetsInfo An array of AssetInfo structs containing detailed information about each asset
     */
    function getUnderlyingAssets() external view override returns (AssetInfo[] memory assetsInfo) {
        return _getUnderlyingAssets(true);
    }

    /**
     * @notice Retrieves information about all the underlying assets that are available to be withdrawn
     * @return assetsInfo An array of AssetInfo structs containing detailed information about each asset
     */
    function getAvailableUnderlyingAssets() public view returns (AssetInfo[] memory assetsInfo) {
        return _getUnderlyingAssets(false);
    }

    /**
     * @notice Retrieves information about all the underlying assets
     * @param total Whether to include assets that are not available to be withdrawn
     * @return assetsInfo An array of AssetInfo structs containing detailed information about each asset
     * @dev This function checks if the asset is a kernel vault and handles the conversion to the underlying asset
     */
    function _getUnderlyingAssets(bool total) public view returns (AssetInfo[] memory assetsInfo) {
        address[] memory assets = vault().getAssets();
        uint256[] memory balances = new uint256[](assets.length);
        bool[] memory assetCounted = new bool[](assets.length);

        uint256 count = 0;

        for (uint256 i = 0; i < assets.length; ++i) {
            address underlyingAsset = _getUnderlyingAsset(assets[i]);
            if (underlyingAsset != address(0) && (total || vault().getSyncWithdraw())) {
                int256 index = findIndex(assets, underlyingAsset);
                if (index >= 0) {
                    balances[uint256(index)] += IERC20Metadata(assets[i]).balanceOf(address(vault()));
                    if (!assetCounted[uint256(index)]) {
                        count++;
                        assetCounted[uint256(index)] = true;
                    }
                }
            } else {
                balances[i] = IERC20Metadata(assets[i]).balanceOf(address(vault()));
                if (!assetCounted[i]) {
                    count++;
                    assetCounted[i] = true;
                }
            }
        }

        address[] memory finalUnderlyingAssets = new address[](count);
        uint256[] memory finalBalances = new uint256[](count);

        uint256 j = 0;
        for (uint256 i = 0; i < assets.length; ++i) {
            if (assetCounted[i]) {
                finalUnderlyingAssets[j] = assets[i];
                finalBalances[j] = balances[i];
                j += 1;
            }
        }

        return _getAssetsInfo(finalUnderlyingAssets, finalBalances);
    }
}
