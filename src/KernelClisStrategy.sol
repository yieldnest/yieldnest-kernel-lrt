// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {KernelStrategy} from "./KernelStrategy.sol";
import {IERC20, Math, SafeERC20} from "lib/yieldnest-vault/src/Common.sol";

import {IWBNB} from "src/interface/external/IWBNB.sol";

import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
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
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals The decimals of the vault.
     * @param baseWithdrawalFee The base withdrawal fee.
     * @param countNativeAsset Whether to count the native asset.
     * @param wbnb The address of the WBNB token.
     * @param clisbnb The address of the CLISBNB token.
     * @param stakerGateway The address of the staker gateway.
     */
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint64 baseWithdrawalFee,
        bool countNativeAsset,
        address wbnb,
        address clisbnb,
        address stakerGateway
    ) external initializer {
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
        vaultStorage.countNativeAsset = countNativeAsset;

        FeeStorage storage fees = _getFeeStorage();
        fees.baseWithdrawalFee = baseWithdrawalFee;

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.stakerGateway = stakerGateway;

        _addAsset(wbnb, decimals, true);
        _addAsset(IStakerGateway(strategyStorage.stakerGateway).getVault(clisbnb), decimals, false);
    }

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

        address wbnb = _getAssetStorage().list[0];
        if (strategyStorage.syncDeposit && asset_ == wbnb) {
            SafeERC20.safeIncreaseAllowance(IERC20(asset_), address(strategyStorage.stakerGateway), assets);

            // unwrap WBNB
            IWBNB(asset_).withdraw(assets);

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

        address wbnb = _getAssetStorage().list[0];
        if (vaultBalance < assets && strategyStorage.syncWithdraw && asset_ == wbnb) {
            // TODO: fix referralId
            string memory referralId = "";
            IStakerGateway(strategyStorage.stakerGateway).unstakeClisBNB(assets, referralId);

            //wrap native token
            IWBNB(asset_).deposit{value: assets}();
        }

        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        _burn(owner, shares);

        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

    /**
     * @dev See {maxWithdrawAsset}.
     */
    function _maxWithdrawAsset(address asset_, address owner) internal view override returns (uint256 maxAssets) {
        if (!_getAssetStorage().assets[asset_].active) {
            return 0;
        }

        (maxAssets,) = _convertToAssets(asset_, balanceOf(owner), Math.Rounding.Floor);

        uint256 availableAssets = IERC20(asset_).balanceOf(address(this));

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        address wbnb = _getAssetStorage().list[0];

        if (strategyStorage.syncWithdraw && asset_ == wbnb) {
            address vault = _getAssetStorage().list[1];
            address clisbnb = IKernelVault(vault).getAsset();
            uint256 availableAssetsInKernel = IERC20(clisbnb).balanceOf(address(vault));
            availableAssets += availableAssetsInKernel;
        }

        if (availableAssets < maxAssets) {
            maxAssets = availableAssets;
        }
    }
}
