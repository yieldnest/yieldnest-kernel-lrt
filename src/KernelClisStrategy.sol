// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {KernelStrategy} from "./KernelStrategy.sol";
import {IERC20, Math, SafeERC20} from "lib/yieldnest-vault/src/Common.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {IWBNB} from "src/interface/external/IWBNB.sol";

contract KernelClisStrategy is KernelStrategy {
    error InvalidDepositAmount(uint256 amount, uint256 amountDesired);
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
     * @notice Deposits a given amount of assets and assigns the equivalent amount of shares to the receiver.
     * @param assets The amount of assets to deposit.
     * @param receiver The address of the receiver.
     * @return uint256 The equivalent amount of shares.
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        if (paused()) {
            revert Paused();
        }
        (uint256 shares, uint256 baseAssets) = _convertToShares(asset(), assets, Math.Rounding.Floor);
        _deposit(asset(), _msgSender(), receiver, assets, shares, baseAssets);
        return shares;
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

        // unwrap WBNB
        IWBNB(asset()).withdraw(assets);

        StrategyStorage storage strategyStorage = _getStrategyStorage();

        if (strategyStorage.syncDeposit) {
            SafeERC20.safeIncreaseAllowance(IERC20(asset_), address(strategyStorage.stakerGateway), assets);

            // TODO: fix referralId
            string memory referralId = "";
            IStakerGateway(strategyStorage.stakerGateway).stakeClisBNB{value: assets}(referralId);
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
            IStakerGateway(strategyStorage.stakerGateway).unstakeClisBNB(assets, referralId);

            //wrap native token
            IWBNB(asset()).deposit{value: assets}();
        }

        SafeERC20.safeTransfer(IERC20(asset_), receiver, assets);

        _burn(owner, shares);

        emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
    }

}
