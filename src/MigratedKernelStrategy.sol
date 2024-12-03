// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {KernelStrategy} from "src/KernelStrategy.sol";
import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {IStakeManager} from "src/interface/external/synclub/IStakeManager.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";

contract MigratedKernelStrategy is KernelStrategy {
    struct ERC4626Storage {
        IERC20 _asset;
        uint8 _underlyingDecimals;
    }

    struct Asset {
        address asset;
        uint8 decimals;
        bool active;
    }

    function _getERC4626Storage() private pure returns (ERC4626Storage storage $) {
        assembly {
            $.slot := 0x0773e532dfede91f04b12a73d3d2acd361424f41f76b4fb79f090161e36b4e00
        }
    }

    function initializeAndMigrate(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals,
        Asset[] calldata assets,
        address stakerGateway,
        bool syncDeposit
    ) external reinitializer(2) {
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

        _migrate(assets, stakerGateway, syncDeposit);
    }

    function _migrate(Asset[] memory assets, address stakerGateway, bool syncDeposit) private {
        ERC4626Storage storage erc4626Storage = _getERC4626Storage();

        // empty storage
        erc4626Storage._asset = IERC20(0x0000000000000000000000000000000000000000);
        erc4626Storage._underlyingDecimals = 0;

        // add new assets
        Asset memory tempAsset;
        for (uint256 i; i < assets.length; i++) {
            tempAsset = assets[i];
            _addAsset(tempAsset.asset, tempAsset.decimals, tempAsset.active);
        }
    }

    function _addAsset(address asset_, uint8 decimals_, bool active_) internal {
        if (asset_ == address(0)) {
            revert ZeroAddress();
        }
        AssetStorage storage assetStorage = _getAssetStorage();
        uint256 index = assetStorage.list.length;
        if (index > 0 && assetStorage.assets[asset_].index != 0) {
            revert DuplicateAsset(asset_);
        }
        assetStorage.assets[asset_] = AssetParams({active: active_, index: index, decimals: decimals_});
        assetStorage.list.push(asset_);

        emit NewAsset(asset_, decimals_, index);
    }
}
