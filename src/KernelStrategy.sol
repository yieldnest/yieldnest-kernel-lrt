// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20, Math, SafeERC20} from "lib/yieldnest-vault/src/Common.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

/**
 * @title KernelStrategy
 * @author Yieldnest
 * @notice This contract is a strategy for Kernel. It is responsible for depositing and withdrawing assets from the
 * vault.
 */
contract KernelStrategy is Vault {
    /// @notice Role for allocator permissions
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    /// @notice Role for kernel dependency manager permissions
    bytes32 public constant KERNEL_DEPENDENCY_MANAGER_ROLE = keccak256("KERNEL_DEPENDENCY_MANAGER_ROLE");

    /// @notice Role for deposit manager permissions
    bytes32 public constant DEPOSIT_MANAGER_ROLE = keccak256("DEPOSIT_MANAGER_ROLE");

    /// @notice Role for allocator manager permissions
    bytes32 public constant ALLOCATOR_MANAGER_ROLE = keccak256("ALLOCATOR_MANAGER_ROLE");

    /// @notice Emitted when an asset is withdrawn
    event WithdrawAsset(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        address asset,
        uint256 assets,
        uint256 shares
    );

    /// @notice Storage structure for strategy-specific parameters
    struct StrategyStorage {
        address stakerGateway;
        bool syncDeposit;
        bool syncWithdraw;
        bool hasAllocators;
    }

    /// @notice Emitted when the staker gateway address is set
    event SetStakerGateway(address stakerGateway);

    /// @notice Emitted when the sync deposit flag is set
    event SetSyncDeposit(bool syncDeposit);

    /// @notice Emitted when the sync withdraw flag is set
    event SetSyncWithdraw(bool syncWithdraw);

    /// @notice Emitted when the hasAllocator flag is set
    event SetHasAllocator(bool hasAllocator);

    /**
     * @notice Returns the current sync deposit flag.
     * @return syncDeposit The sync deposit flag.
     */
    function getSyncDeposit() public view returns (bool syncDeposit) {
        return _getStrategyStorage().syncDeposit;
    }

    /**
     * @notice Returns the current sync withdraw flag.
     * @return syncWithdraw The sync withdraw flag.
     */
    function getSyncWithdraw() public view returns (bool syncWithdraw) {
        return _getStrategyStorage().syncWithdraw;
    }

    /**
     * @notice Returns the staker gateway address.
     * @return stakerGateway The staker gateway address.
     */
    function getStakerGateway() public view returns (address stakerGateway) {
        return _getStrategyStorage().stakerGateway;
    }

    /**
     * @notice Returns whether the strategy has allocators.
     * @return hasAllocators True if the strategy has allocators, otherwise false.
     */
    function getHasAllocator() public view returns (bool hasAllocators) {
        return _getStrategyStorage().hasAllocators;
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn by a given owner.
     * @param owner The address of the owner.
     * @return maxAssets The maximum amount of assets.
     */
    function maxWithdraw(address owner) public view override returns (uint256 maxAssets) {
        maxAssets = _maxWithdrawAsset(asset(), owner);
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn for a specific asset by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxAssets The maximum amount of assets.
     */
    function maxWithdrawAsset(address asset_, address owner) public view returns (uint256 maxAssets) {
        maxAssets = _maxWithdrawAsset(asset_, owner);
    }

    /**
     * @notice Internal function to get the maximum amount of assets that can be withdrawn by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxAssets The maximum amount of assets.
     */
    function _maxWithdrawAsset(address asset_, address owner) internal view virtual returns (uint256 maxAssets) {
        if (paused() || !_getAssetStorage().assets[asset_].active) {
            return 0;
        }

        uint256 availableAssets = _availableAssets(asset_);

        maxAssets = previewRedeemAsset(asset_, balanceOf(owner));

        maxAssets = availableAssets < maxAssets ? availableAssets : maxAssets;
    }

    /**
     * @notice Internal function to get the available amount of assets.
     * @param asset_ The address of the asset.
     * @return availableAssets The available amount of assets.
     */
    function _availableAssets(address asset_) internal view virtual returns (uint256 availableAssets) {
        availableAssets = IERC20(asset_).balanceOf(address(this));

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        if (strategyStorage.syncWithdraw) {
            uint256 availableAssetsInKernel =
                IStakerGateway(strategyStorage.stakerGateway).balanceOf(asset_, address(this));
            availableAssets += availableAssetsInKernel;
        }
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by a given owner.
     * @param owner The address of the owner.
     * @return maxShares The maximum amount of shares.
     */
    function maxRedeem(address owner) public view override returns (uint256 maxShares) {
        maxShares = _maxRedeemAsset(asset(), owner);
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxShares The maximum amount of shares.
     */
    function maxRedeemAsset(address asset_, address owner) public view returns (uint256 maxShares) {
        maxShares = _maxRedeemAsset(asset_, owner);
    }

    /**
     * @notice Internal function to get the maximum amount of shares that can be redeemed by a given owner.
     * @param asset_ The address of the asset.
     * @param owner The address of the owner.
     * @return maxShares The maximum amount of shares.
     */
    function _maxRedeemAsset(address asset_, address owner) internal view virtual returns (uint256 maxShares) {
        if (paused() || !_getAssetStorage().assets[asset_].active) {
            return 0;
        }

        uint256 availableAssets = _availableAssets(asset_);

        maxShares = balanceOf(owner);

        maxShares = availableAssets < previewRedeemAsset(asset_, maxShares)
            ? previewWithdrawAsset(asset_, availableAssets)
            : maxShares;
    }

    /**
     * @notice Previews the amount of assets that would be required to mint a given amount of shares.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to mint.
     * @return assets The equivalent amount of assets.
     */
    function previewMintAsset(address asset_, uint256 shares) public view virtual returns (uint256 assets) {
        (assets,) = _convertToAssets(asset_, shares, Math.Rounding.Ceil);
    }

    /**
     * @notice Previews the amount of shares that would be received for a given amount of assets.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to deposit.
     * @return shares The equivalent amount of shares.
     */
    function previewWithdrawAsset(address asset_, uint256 assets) public view virtual returns (uint256 shares) {
        uint256 fee = _feeOnRaw(assets);
        (shares,) = _convertToShares(asset_, assets + fee, Math.Rounding.Ceil);
    }

    /**
     * @notice Previews the amount of assets that would be received for a given amount of shares.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to redeem.
     * @return assets The equivalent amount of assets.
     */
    function previewRedeemAsset(address asset_, uint256 shares) public view virtual returns (uint256 assets) {
        (assets,) = _convertToAssets(asset_, shares, Math.Rounding.Floor);
        assets = assets - _feeOnTotal(assets);
    }

    /**
     * @notice Withdraws a given amount of assets and burns the equivalent amount of shares from the owner.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return shares The equivalent amount of shares.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 shares)
    {
        shares = _withdrawAsset(asset(), assets, receiver, owner);
    }

    /**
     * @notice Withdraws assets and burns equivalent shares from the owner.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return shares The equivalent amount of shares burned.
     */
    function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        public
        virtual
        nonReentrant
        returns (uint256 shares)
    {
        shares = _withdrawAsset(asset_, assets, receiver, owner);
    }

    /**
     * @notice Internal function for withdraws assets and burns equivalent shares from the owner.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return shares The equivalent amount of shares burned.
     */
    function _withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        internal
        returns (uint256 shares)
    {
        if (paused()) {
            revert Paused();
        }
        uint256 maxAssets = maxWithdrawAsset(asset_, owner);
        if (assets > maxAssets) {
            revert ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        shares = previewWithdrawAsset(asset_, assets);
        _withdrawAsset(asset_, _msgSender(), receiver, owner, assets, shares);
    }

    /**
     * @notice Redeems a given amount of shares and transfers the equivalent amount of assets to the receiver.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return assets The equivalent amount of assets.
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 assets)
    {
        assets = _redeemAsset(asset(), shares, receiver, owner);
    }

    /**
     * @notice Redeems shares and transfers equivalent assets to the receiver.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return assets The equivalent amount of assets.
     */
    function redeemAsset(address asset_, uint256 shares, address receiver, address owner)
        public
        virtual
        nonReentrant
        returns (uint256 assets)
    {
        assets = _redeemAsset(asset_, shares, receiver, owner);
    }

    /**
     * @notice Internal function for redeems shares and transfers equivalent assets to the receiver.
     * @param asset_ The address of the asset.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return assets The equivalent amount of assets.
     */
    function _redeemAsset(address asset_, uint256 shares, address receiver, address owner)
        internal
        returns (uint256 assets)
    {
        if (paused()) {
            revert Paused();
        }
        uint256 maxShares = maxRedeemAsset(asset_, owner);
        if (shares > maxShares) {
            revert ExceededMaxRedeem(owner, shares, maxShares);
        }
        assets = previewRedeemAsset(asset_, shares);
        _withdrawAsset(asset_, _msgSender(), receiver, owner, assets, shares);
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
    ) internal virtual override onlyAllocator {
        super._deposit(asset_, caller, receiver, assets, shares, baseAssets);

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        if (strategyStorage.syncDeposit) {
            _stake(asset_, assets, IStakerGateway(strategyStorage.stakerGateway));
        }
    }

    /**
     * @notice Internal function to stake assets into the Kernel protocol
     * @dev This function handles the staking of assets through the staker gateway.
     * @param asset_ The address of the asset to stake
     * @param assets The amount of assets to stake
     * @param stakerGateway The staker gateway contract to use for staking
     */
    function _stake(address asset_, uint256 assets, IStakerGateway stakerGateway) internal virtual {
        // For other assets, stake directly
        SafeERC20.safeIncreaseAllowance(IERC20(asset_), address(stakerGateway), assets);

        string memory referralId = ""; // Placeholder referral ID
        stakerGateway.stake(asset_, assets, referralId);
    }

    /**
     * @notice Internal function to handle withdrawals.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @param assets The amount of assets to withdraw.
     * @param shares The equivalent amount of shares.
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        _withdrawAsset(asset(), caller, receiver, owner, assets, shares);
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
    ) internal virtual onlyAllocator {
        if (!_getAssetStorage().assets[asset_].active) {
            revert AssetNotActive();
        }

        _subTotalAssets(_convertAssetToBase(asset_, assets));

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        uint256 vaultBalance = IERC20(asset_).balanceOf(address(this));

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        if (vaultBalance < assets && strategyStorage.syncWithdraw) {
            _unstake(asset_, assets - vaultBalance, IStakerGateway(strategyStorage.stakerGateway));
        }

        // NOTE: burn shares before withdrawing the assets
        _burn(owner, shares);

        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

    /**
     * @notice Internal function to unstake assets from Kernel.
     * @param asset_ The address of the asset to unstake.
     * @param amount The amount of assets to unstake.
     * @param stakerGateway The address of the staker gateway.
     */
    function _unstake(address asset_, uint256 amount, IStakerGateway stakerGateway) internal virtual {
        string memory referralId = ""; // Placeholder referral ID
        stakerGateway.unstake(asset_, amount, referralId);
    }

    /**
     * @notice Retrieves the strategy storage structure.
     * @return $ The strategy storage structure.
     */
    function _getStrategyStorage() internal pure virtual returns (StrategyStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.strategy")
            $.slot := 0x0ef3e973c65e9ac117f6f10039e07687b1619898ed66fe088b0fab5f5dc83d88
        }
    }

    /**
     * @notice Sets the staker gateway address.
     * @param stakerGateway The address of the staker gateway.
     */
    function setStakerGateway(address stakerGateway) external onlyRole(KERNEL_DEPENDENCY_MANAGER_ROLE) {
        if (stakerGateway == address(0)) revert ZeroAddress();

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.stakerGateway = stakerGateway;

        emit SetStakerGateway(stakerGateway);
    }

    /**
     * @notice Sets the sync deposit flag.
     * @param syncDeposit The new value for the sync deposit flag.
     */
    function setSyncDeposit(bool syncDeposit) external onlyRole(DEPOSIT_MANAGER_ROLE) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.syncDeposit = syncDeposit;

        emit SetSyncDeposit(syncDeposit);
    }

    /**
     * @notice Sets the sync withdraw flag.
     * @param syncWithdraw The new value for the sync withdraw flag.
     */
    function setSyncWithdraw(bool syncWithdraw) external onlyRole(DEPOSIT_MANAGER_ROLE) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.syncWithdraw = syncWithdraw;

        emit SetSyncWithdraw(syncWithdraw);
    }

    /**
     * @notice Sets whether the strategy has allocators.
     * @param hasAllocators_ The new value for the hasAllocator flag.
     */
    function setHasAllocator(bool hasAllocators_) external onlyRole(ALLOCATOR_MANAGER_ROLE) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.hasAllocators = hasAllocators_;

        emit SetHasAllocator(hasAllocators_);
    }

    /**
     * @notice Adds a new asset to the vault.
     * @param asset_ The address of the asset.
     * @param decimals_ The decimals of the asset.
     * @param active_ Whether the asset is active.
     */
    function addAssetWithDecimals(address asset_, uint8 decimals_, bool active_)
        public
        virtual
        onlyRole(ASSET_MANAGER_ROLE)
    {
        _addAsset(asset_, decimals_, active_);
    }

    /**
     * @notice Modifier to restrict access to allocator roles.
     */
    modifier onlyAllocator() {
        if (_getStrategyStorage().hasAllocators && !hasRole(ALLOCATOR_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, ALLOCATOR_ROLE);
        }
        _;
    }
}
