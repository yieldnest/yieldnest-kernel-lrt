// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";

/**
 * @title MigratedKernelStrategy
 * @dev This contract extends KernelStrategy to include migration functionality for ERC4626 storage and assets.
 */
contract MigratedKernelStrategy is KernelStrategy {
    /**
     * @dev Storage structure for ERC4626 asset information.
     * @param _asset The ERC20 token associated with the strategy.
     * @param _underlyingDecimals The number of decimals of the underlying asset.
     */
    struct ERC4626Storage {
        IERC20 _asset;
        uint8 _underlyingDecimals;
    }

    /**
     * @dev Structure to represent an asset's details.
     * @param asset The address of the asset.
     * @param active Whether the asset is active.
     */
    struct Asset {
        address asset;
        bool active;
    }

    /**
     * @notice Retrieves the storage location for ERC4626 storage.
     * @dev The storage slot is hardcoded for optimized access.
     * @return $ The ERC4626Storage reference at the designated slot.
     */
    function _getERC4626Storage() private pure returns (ERC4626Storage storage $) {
        assembly {
            $.slot := 0x0773e532dfede91f04b12a73d3d2acd361424f41f76b4fb79f090161e36b4e00
        }
    }

    /**
     * @notice Initializes and migrates the kernel strategy vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param assets The array of Asset structs containing addresses and active states.
     * @param stakerGateway The address of the staker gateway.
     * @param baseWithdrawalFee The base fee for withdrawals.
     */
    function initializeAndMigrate(
        address admin,
        string memory name,
        string memory symbol,
        Asset[] calldata assets,
        address stakerGateway,
        uint64 baseWithdrawalFee
    ) external reinitializer(2) {
        _initialize(admin, name, symbol, 18, baseWithdrawalFee, true, true);

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.stakerGateway = stakerGateway;
        strategyStorage.syncDeposit = true;
        strategyStorage.syncWithdraw = true;

        _migrate(assets);
    }

    /**
     * @notice Migrates assets to the vault and resets ERC4626 storage.
     * @dev This function clears the previous storage and adds new assets.
     * @param assets The array of assets to be added to the vault.
     */
    function _migrate(Asset[] memory assets) private {
        ERC4626Storage storage erc4626Storage = _getERC4626Storage();

        // Clear existing storage
        erc4626Storage._asset = IERC20(0x0000000000000000000000000000000000000000);
        erc4626Storage._underlyingDecimals = 0;

        // Add new assets
        Asset memory tempAsset;
        for (uint256 i; i < assets.length; i++) {
            tempAsset = assets[i];

            _addAsset(tempAsset.asset, 18, tempAsset.active);
        }
    }
}
