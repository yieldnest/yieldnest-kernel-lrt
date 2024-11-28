// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {SafeERC20, Math, IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {IHasConfigUpgradeable} from "lib/kernel/src/interfaces/IHasConfigUpgradeable.sol";
import {IKernelConfig} from "lib/kernel/src/interfaces/IKernelConfig.sol";
import {IStakerGateway} from "lib/kernel/src/interfaces/IStakerGateway.sol";

contract ynBNBStrategy is BaseVault {
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    address public stakerGateway;
    address public assetRegistry;
    /**
     * @notice Initializes the vault.
     * @param admin The address of the admin.
     * @param name The name of the vault.
     * @param symbol The symbol of the vault.
     */
    function initialize(address admin, string memory name, string memory symbol, uint8 decimals, address _stakerGateway) external initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.paused = true;
        vaultStorage.decimals = decimals;
        stakerGateway = _stakerGateway;
        assetRegistry = IKernelConfig(IHasConfigUpgradeable(_stakerGateway).getConfig()).getAssetRegistry();
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn by a given owner.
     * @param owner The address of the owner.
     * @return uint256 The maximum amount of assets.
     * @dev override the maxWithdraw function for strategies
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (paused()) {
            return 0;
        }

        uint256 ownerShares = balanceOf(owner);
        uint256 maxAssets = convertToAssets(ownerShares);

        return maxAssets;
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
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets += baseAssets;

        SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);

        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
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
        onlyRole(ALLOCATOR_ROLE)
    {
        VaultStorage storage vaultStorage = _getVaultStorage();
        vaultStorage.totalAssets -= assets;
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);

        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _verifyAsset(address asset)internal returns(bool){
        return IAssetRegistry(assetRegistry).hasAsset(asset);
    }
    /**
     * @notice Deposits a given amount of assets and assigns the equivalent amount of shares to the receiver.
     * @param asset The asset address
     * @param amount The amount of assets to deposit.
     * @param receiver The address of the receiver.
     * @return uint256 The equivalent amount of shares.
     */
    function deposit(address asset, uint256 amount, address receiver) public virtual nonReentrant returns (uint256) {
        if (paused()) {
            revert Paused();
        }
        require(_verifyAsset(asset), "Not an allowed asset");
        (uint256 shares, uint256 baseAssets) = _convertToShares(asset, amount, Math.Rounding.Floor);
        _deposit(asset, _msgSender(), receiver, amount, shares, baseAssets);
        return shares;
    }

    /**
     * @notice Withdraws a given amount of assets and burns the equivalent amount of shares from the owner.
     * @param asset The asset address
     * @param amount The amount of assets to withdraw.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return shares The equivalent amount of shares.
     */
    function withdraw(address asset, uint256 amount, address receiver, address owner)
        public
        virtual
        nonReentrant
        returns (uint256 shares)
    {
        if (paused()) {
            revert Paused();
        }
        uint256 maxAssets = maxWithdraw(owner);
        if (amount > maxAssets) {
            revert ExceededMaxWithdraw(owner, amount, maxAssets);
        }
        (shares,) = _convertToShares(asset, amount, Math.Rounding.Ceil);
        _withdraw(_msgSender(), receiver, owner, amount, shares);
    }
}
