// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {KernelStrategy} from "./KernelStrategy.sol";
import {IERC20, SafeERC20} from "lib/yieldnest-vault/src/Common.sol";

import {IWBNB} from "src/interface/external/IWBNB.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

/**
 * @title KernelClisStrategy
 * @author Yieldnest
 * @notice This contract is a strategy for Kernel. It is responsible for depositing and withdrawing assets from the
 * vault.
 * @dev This contract modifies the deposit and withdraw functions of the Vault to handle the deposits and withdrawals
 * for the specific asset clisBNB.
 */
contract KernelClisStrategy is KernelStrategy {
    /**
     * @notice Internal function to handle deposits.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param assets The amount of assets to deposit.
     * @param shares The amount of shares to mint.
     * @param baseAssets The base asset conversion of shares.
     */
    function _deposit(
        address asset_,
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 baseAssets
    ) internal override onlyRole(ALLOCATOR_ROLE) {
        if (!_getAssetStorage().assets[asset_].active) {
            revert AssetNotActive();
        }

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets += baseAssets;

        SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);
        _mint(receiver, shares);

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        // if sync deposit is false we keep the WBNB wrapped and unwrap it with the processor

        if (strategyStorage.syncDeposit) {
            SafeERC20.safeIncreaseAllowance(IERC20(asset_), address(strategyStorage.stakerGateway), assets);

            // unwrap WBNB
            IWBNB(asset()).withdraw(assets);

            // TODO: fix referralId
            string memory referralId = "";
            IStakerGateway(strategyStorage.stakerGateway).stakeClisBNB{value: assets}(referralId);
        }

        emit DepositAsset(caller, receiver, asset_, assets, shares);
    }

    /**
     * @notice Internal function to handle withdrawals for specific assets.
     * @param asset_ The address of the asset.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @param assets The amount of assets to withdraw.
     * @param shares The equivalent amount of shares.
     */
    function _withdrawAsset(
        address asset_,
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override onlyRole(ALLOCATOR_ROLE) {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets -= assets;
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        uint256 vaultBalance = IERC20(asset_).balanceOf(address(this));

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        if (vaultBalance < assets && strategyStorage.syncWithdraw) {
            // TODO: fix referralId
            string memory referralId = "";
            IStakerGateway(strategyStorage.stakerGateway).unstakeClisBNB(assets - vaultBalance, referralId);

            //wrap native token
            IWBNB(asset()).deposit{value: assets}();
        }

        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        _burn(owner, shares);

        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }
}
