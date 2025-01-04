// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {KernelStrategy} from "./KernelStrategy.sol";

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {IWBNB} from "src/interface/external/IWBNB.sol";

import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

/**
 * @title KernelClisStrategy
 * @author Yieldnest
 * @notice This contract is a strategy for Kernel. It is responsible for depositing and withdrawing assets from the
 * vault.
 * @dev This contract modifies the deposit and withdraw functions of the Vault to handle the deposits and withdrawals
 * for the specific asset clisBNB. It's meant to only support WNBNB as primary deposit asset.
 */
contract KernelClisStrategy is KernelStrategy {
    function _stake(address asset_, uint256 assets, IStakerGateway stakerGateway) internal virtual override {
        if (asset_ != asset()) {
            revert InvalidAsset(asset_);
        }
        // unwrap WBNB
        IWBNB(asset_).withdraw(assets);

        // Placeholder referralId
        string memory referralId = "";
        stakerGateway.stakeClisBNB{value: assets}(referralId);
    }

    function _unstake(address asset_, uint256 assets, IStakerGateway stakerGateway) internal virtual override {
        if (asset_ != asset()) {
            revert InvalidAsset(asset_);
        }
        // Placeholder referralId
        string memory referralId = "";
        stakerGateway.unstakeClisBNB(assets, referralId);

        //wrap native token
        IWBNB(asset_).deposit{value: assets}();
    }

    function _availableAssets(address asset_) internal view virtual override returns (uint256 availableAssets) {
        availableAssets = IERC20(asset_).balanceOf(address(this));

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        if (strategyStorage.syncWithdraw && asset_ == asset()) {
            IStakerGateway stakerGateway = IStakerGateway(strategyStorage.stakerGateway);
            address clisbnb = IKernelConfig(stakerGateway.getConfig()).getClisBnbAddress();
            uint256 availableAssetsInKernel = stakerGateway.balanceOf(clisbnb, address(this));
            availableAssets += availableAssetsInKernel;
        }
    }
}
