// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/console.sol";
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

    /// @notice Emitted when an asset is deposited
    event DepositAsset(
        address indexed sender, address indexed receiver, address indexed asset, uint256 assets, uint256 shares
    );

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
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     * @param decimals The decimals of the vault.
     * @param baseWithdrawalFee The base withdrawal fee.
     * @param countNativeAsset Whether to count the native asset.
     */
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint64 baseWithdrawalFee,
        bool countNativeAsset
    ) external virtual override initializer {
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
    }

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
        if (paused()) {
            return 0;
        }

        (maxAssets,) = _convertToAssets(asset(), balanceOf(owner), Math.Rounding.Floor);
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by a given owner.
     * @param owner The address of the owner.
     * @return maxShares The maximum amount of shares.
     */
    function maxRedeem(address owner) public view override returns (uint256 maxShares) {
        if (paused()) {
            return 0;
        }

        return balanceOf(owner);
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

        return assets - _feeOnTotal(assets);
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
        if (paused()) {
            revert Paused();
        }
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        shares = previewWithdrawAsset(asset_, assets);
        _withdrawAsset(asset_, _msgSender(), receiver, owner, assets, shares);
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
        if (paused()) {
            revert Paused();
        }
        uint256 maxShares = maxRedeem(owner);
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
        if (!_getAssetStorage().assets[asset_].active) {
            revert AssetNotActive();
        }

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets += baseAssets;

        SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);
        _mint(receiver, shares);

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        if (strategyStorage.syncDeposit) {
            SafeERC20.safeIncreaseAllowance(IERC20(asset_), address(strategyStorage.stakerGateway), assets);

            string memory referralId = ""; // Placeholder referral ID
            IStakerGateway(strategyStorage.stakerGateway).stake(asset_, assets, referralId);
        }

        emit DepositAsset(caller, receiver, asset_, assets, shares);
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
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets -= _convertAssetToBase(asset_, assets);
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        uint256 vaultBalance = IERC20(asset_).balanceOf(address(this));

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        if (vaultBalance < assets && strategyStorage.syncWithdraw) {
            console.log("unstaking");
            string memory referralId = ""; // Placeholder referral ID
            IStakerGateway(strategyStorage.stakerGateway).unstake(asset_, assets, referralId);
        }

        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        _burn(owner, shares);

        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

    /**
     * @notice Retrieves the strategy storage structure.
     * @return $ The strategy storage structure.
     */
    function _getStrategyStorage() internal pure virtual returns (StrategyStorage storage $) {
        assembly {
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
