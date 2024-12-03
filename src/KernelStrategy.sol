// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {Math, SafeERC20, IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

contract KernelStrategy is BaseVault {
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");

    event DepositAsset(
        address indexed sender, address indexed receiver, address indexed asset, uint256 assets, uint256 shares
    );

    event WithdrawAsset(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        address asset,
        uint256 assets,
        uint256 shares
    );

    struct StrategyStorage {
        address stakerGateway;
        bool syncDeposit;
    }

    event SetStakerGateway(address stakerGateway);
    event SetSyncDeposit(bool syncDeposit);

    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     */
    function initialize(address admin, string memory name, string memory symbol, uint8 decimals) external initializer {
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
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn by a given owner.
     * @param owner The address of the owner.
     * @return maxAssets uint256 The maximum amount of assets.
     * @dev override the maxWithdraw function for strategies
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
     * @return uint256 The maximum amount of shares.
     * @dev override the maxRedeem function for strategies
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        if (paused()) {
            return 0;
        }

        return balanceOf(owner);
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn by a given owner.
     * @param owner The address of the owner.
     * @return maxAssets uint256 The maximum amount of assets.
     * @dev override the maxWithdraw function for strategies
     */
    function maxWithdrawAsset(address asset_, address owner) public view returns (uint256 maxAssets) {
        if (paused()) {
            return 0;
        }

        (maxAssets,) = _convertToAssets(asset_, balanceOf(owner), Math.Rounding.Floor);
    }

    /**
     * @notice Previews the amount of shares that would be received for a given amount of assets for a specific asset.
     * @param asset_ The address of the asset.
     * @param assets The amount of assets to deposit.
     * @return shares The equivalent amount of shares.
     */
    function previewWithdrawAsset(address asset_, uint256 assets) public view virtual returns (uint256 shares) {
        (shares,) = _convertToShares(asset_, assets, Math.Rounding.Floor);
    }

    /**
     * @notice Previews the amount of assets that would be received for a given amount of shares.
     * @param shares The amount of shares to redeem.
     * @return assets The equivalent amount of assets.
     */
    function previewRedeemAsset(address asset_, uint256 shares) public view virtual returns (uint256 assets) {
        (assets,) = _convertToAssets(asset_, shares, Math.Rounding.Floor);
    }

    /**
     * @notice Withdraws a given amount of assets and burns the equivalent amount of shares from the owner.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return shares The equivalent amount of shares.
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
     * @param baseAssets The base asset convertion of shares.
     * @dev This is an example:
     *     The _deposit function for strategies needs an override
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
        if (strategyStorage.syncDeposit) {
            IStakerGateway stakerGateway = IStakerGateway(strategyStorage.stakerGateway);

            SafeERC20.safeIncreaseAllowance(IERC20(asset_), address(stakerGateway), assets);

            // TODO: fix referralId
            string memory referralId = "";
            stakerGateway.stake(asset_, assets, referralId);
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
     * @dev This is an example:
     *     The _withdraw function for strategies needs an override
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _withdrawAsset(asset(), caller, receiver, owner, assets, shares);
    }

    /**
     * @notice Internal function to handle withdrawals.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @param assets The amount of assets to withdraw.
     * @param shares The equivalent amount of shares.
     * @dev This is an example:
     *     The _withdraw function for strategies needs an override
     */
    function _withdrawAsset(
        address asset_,
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal onlyRole(ALLOCATOR_ROLE) {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets -= assets;
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        IStakerGateway stakerGateway = IStakerGateway(strategyStorage.stakerGateway);

        // TODO: fix referralId
        string memory referralId = "";
        stakerGateway.unstake(asset_, assets, referralId);

        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        _burn(owner, shares);
        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

    /**
     * @notice Internal function to get the vault storage.
     * @return $ The vault storage.
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
    function setStakerGateway(address stakerGateway) external onlyRole(STRATEGY_MANAGER_ROLE) {
        if (stakerGateway == address(0)) revert ZeroAddress();

        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.stakerGateway = stakerGateway;

        emit SetStakerGateway(stakerGateway);
    }

    /**
     * @notice Sets the direct deposit flag.
     * @param syncDeposit The flag.
     */
    function setSyncDeposit(bool syncDeposit) external onlyRole(STRATEGY_MANAGER_ROLE) {
        StrategyStorage storage strategyStorage = _getStrategyStorage();
        strategyStorage.syncDeposit = syncDeposit;

        emit SetSyncDeposit(syncDeposit);
    }
}
