// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

interface IKernelProvider is IProvider {
    error UnsupportedAsset(address asset);
    error AssetMismatch(address vault, address asset);

    /**
     * @notice Returns the staker gateway address
     * @return The staker gateway address
     */
    function getStakerGateway() external view returns (address);

    /**
     * @notice Returns the vault asset if the given vault is a kernel vault
     * @param vault The vault to get the asset for
     * @return The vault asset
     */
    function tryGetVaultAsset(address vault) external view returns (address);

    /**
     * @notice Returns the rate of the given asset
     * @param asset The asset to get the rate for
     * @return The rate of the asset
     */
    function getRate(address asset) external view returns (uint256);
}
