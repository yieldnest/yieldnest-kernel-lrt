// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {KernelStrategy} from "src/KernelStrategy.sol";
import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {IStakeManager} from "src/interface/external/synclub/IStakeManager.sol";

import {console} from "lib/forge-std/src/console.sol";

contract MigrateKernelStrategy is KernelStrategy {
    struct ERC4626Storage {
        IERC20 _asset;
        uint8 _underlyingDecimals;
    }

    function _getERC4626Storage() private pure returns (ERC4626Storage storage $) {
        assembly {
            $.slot := 0x0773e532dfede91f04b12a73d3d2acd361424f41f76b4fb79f090161e36b4e00
        }
    }

    function initializeAndMigrate(address admin, string memory name, string memory symbol, uint8 decimals)
        external
        reinitializer(2)
    {
        if (admin == address(0)) {
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
        _migrate();
    }

    function _migrate() internal {
        ERC4626Storage storage erc4626Storage = _getERC4626Storage();

        address asset_ = address(erc4626Storage._asset);
        uint8 decimals_ = erc4626Storage._underlyingDecimals;

        // add asset
        AssetStorage storage assetStorage = _getAssetStorage();
        assetStorage.assets[asset_] = AssetParams({active: true, index: 0, decimals: decimals_});
        assetStorage.list.push(asset_);

        emit NewAsset(asset_, decimals_, 0);

        // process accounting
        IStakeManager stakeManager = IStakeManager(0x1adB950d8bB3dA4bE104211D5AB038628e477fE6);
        uint256 assetBalance = erc4626Storage._asset.balanceOf(address(this));
        uint256 totalBaseBalance = address(this).balance;
        totalBaseBalance += stakeManager.convertSnBnbToBnb(assetBalance);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets = totalBaseBalance;

        erc4626Storage._asset = IERC20(0x0000000000000000000000000000000000000000);
        erc4626Storage._underlyingDecimals = 0;
    }
}
