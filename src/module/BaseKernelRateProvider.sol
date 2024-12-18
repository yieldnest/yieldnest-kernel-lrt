// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IKernelProvider} from "src/interface/IKernelProvider.sol";

import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

/**
 * @title BaseKernelRateProvider
 * @author Yieldnest
 * @notice Provides the rate of an asset for the Yieldnest Kernel
 * @dev This contract is meant to be inherited by other rate providers
 */
abstract contract BaseKernelRateProvider is IKernelProvider {
    /**
     * @notice Returns the staker gateway address
     * @return The staker gateway address
     */
    function getStakerGateway() public view virtual returns (address);

    /**
     * @notice Returns the vault asset if the given vault is a kernel vault
     * @param vault The vault to get the asset for
     * @return The vault asset
     */
    function tryGetVaultAsset(address vault) public view returns (address) {
        try IKernelVault(vault).getAsset() returns (address asset) {
            if (IStakerGateway(getStakerGateway()).getVault(asset) != vault) {
                revert AssetMismatch(vault, asset);
            }
            return asset;
        } catch {
            return address(0);
        }
    }

    /**
     * @notice Returns the rate of the given asset
     * @param asset The asset to get the rate for
     * @return The rate of the asset
     */
    function getRate(address asset) public view virtual returns (uint256);
}
