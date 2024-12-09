// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";

contract MigratedKernelStrategy is KernelStrategy {
    struct ERC4626Storage {
        IERC20 _asset;
        uint8 _underlyingDecimals;
    }

    struct Asset {
        address asset;
        bool active;
    }

    function _getERC4626Storage() private pure returns (ERC4626Storage storage $) {
        assembly {
            $.slot := 0x0773e532dfede91f04b12a73d3d2acd361424f41f76b4fb79f090161e36b4e00
        }
    }

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals The decimals of the vault.
     * @param assets The assets of the vault.
     * @param stakerGateway The staker gateway.
     * @param syncDeposit Whether to sync deposit.
     * @param syncWithdraw Whether to sync withdraw.
     * @param baseWithdrawalFee The base withdrawal fee.
     * @param countNativeAsset Whether to count native asset.
     */
    function initializeAndMigrate(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals,
        Asset[] calldata assets,
        address stakerGateway,
        bool syncDeposit,
        bool syncWithdraw,
        uint64 baseWithdrawalFee,
        bool countNativeAsset
    ) external reinitializer(2) {
        if (admin == address(0)) {
            revert ZeroAddress();
        }
        if (stakerGateway == address(0)) {
            revert ZeroAddress();
        }

        __ERC20Permit_init(name);
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
        vaultStorage.decimals = decimals;
        vaultStorage.countNativeAsset = countNativeAsset;

        FeeStorage storage fees = _getFeeStorage();
        fees.baseWithdrawalFee = baseWithdrawalFee;

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.stakerGateway = stakerGateway;
        strategyStorage.syncDeposit = syncDeposit;
        strategyStorage.syncWithdraw = syncWithdraw;

        _migrate(assets, decimals);
    }

    function _migrate(Asset[] memory assets, uint8 decimals) private {
        ERC4626Storage storage erc4626Storage = _getERC4626Storage();

        // empty storage
        erc4626Storage._asset = IERC20(0x0000000000000000000000000000000000000000);
        erc4626Storage._underlyingDecimals = 0;

        // add new assets
        Asset memory tempAsset;
        for (uint256 i; i < assets.length; i++) {
            tempAsset = assets[i];

            _addAsset(tempAsset.asset, decimals, tempAsset.active);
        }
    }
}
