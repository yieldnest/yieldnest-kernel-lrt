// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MainnetKernelActors} from "script/KernelActors.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";
import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";

import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";

contract BaseForkTest is Test, MainnetKernelActors, ProxyUtils {
    IStakerGateway public stakerGateway;
    KernelStrategy public vault;
    IERC20 public asset;
    address public alice = address(0xA11c3);

    function _getStakedBalance() internal view virtual returns (uint256) {
        return stakerGateway.balanceOf(address(asset), address(vault));
    }

    function _depositIntoVault(address depositor, uint256 depositAmount) internal virtual {
        // Initial balances
        uint256 depositorAssetBefore = asset.balanceOf(depositor);
        uint256 depositorSharesBefore = vault.balanceOf(depositor);

        // Store initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();
        // Store initial vault Asset balance
        uint256 vaultAssetBefore = _getStakedBalance();

        // Give depositor some asset
        deal(address(asset), depositor, depositorAssetBefore + depositAmount);

        assertEq(asset.balanceOf(depositor), depositorAssetBefore + depositAmount, "Asset balance incorrect after deal");

        vm.startPrank(depositor);
        // Approve vault to spend Asset
        asset.approve(address(vault), depositAmount);
        // Deposit Asset to get shares
        uint256 shares = vault.deposit(depositAmount, depositor);

        vm.stopPrank();

        // Check balances after deposit
        assertEq(asset.balanceOf(depositor), depositorAssetBefore, "Asset balance incorrect");
        assertEq(vault.balanceOf(depositor), depositorSharesBefore + shares, "Should have received shares");

        // Check vault state after deposit
        assertEq(
            vault.totalAssets(), initialTotalAssets + depositAmount, "Total assets should increase by deposit amount"
        );
        assertEq(vault.totalSupply(), initialTotalSupply + shares, "Total supply should increase by shares");

        // Check that vault Asset balance increased by deposit amount
        assertEq(_getStakedBalance(), vaultAssetBefore + depositAmount, "Vault balance should increase by deposit");
    }

    function _withdrawFromVault(address withdrawer, uint256 withdrawAmount) internal virtual {
        // Initial balances
        uint256 withdrawerAssetBefore = asset.balanceOf(withdrawer);
        uint256 withdrawerSharesBefore = vault.balanceOf(withdrawer);

        // Store initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();

        // Store initial vault Asset balance
        uint256 vaultAssetBefore = _getStakedBalance();

        vm.startPrank(withdrawer);

        // Deposit Asset to get shares
        uint256 shares = KernelStrategy(payable(address(vault))).withdrawAsset(
            address(asset), withdrawAmount, withdrawer, withdrawer
        );

        vm.stopPrank();

        // Check balances after deposit
        assertEq(asset.balanceOf(withdrawer), withdrawerAssetBefore + withdrawAmount, "Asset balance incorrect");
        assertEq(vault.balanceOf(withdrawer), withdrawerSharesBefore - shares, "Should have burnt shares");

        // Check vault state after deposit
        assertEq(
            vault.totalAssets(), initialTotalAssets - withdrawAmount, "Total assets should decrease by withdraw amount"
        );
        assertEq(vault.totalSupply(), initialTotalSupply - shares, "Total supply should decrease by shares");

        // Check that vault Asset balance increased by deposit amount
        assertEq(
            _getStakedBalance(), vaultAssetBefore - withdrawAmount, "Vault balance should decrease by withdraw amount"
        );
    }

    function _upgradeVault() internal virtual {
        address newImplementation = address(new KernelStrategy());
        _upgradeVaultWithTimelock(address(newImplementation));
    }

    function _upgradeVaultWithTimelock(address newImplementation) internal virtual {
        address vaultAddress = address(vault);

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(getProxyAdmin(vaultAddress));

        TimelockController timelock = TimelockController(payable(proxyAdmin.owner()));

        // Encode upgrade call
        bytes memory upgradeData =
            abi.encodeWithSelector(proxyAdmin.upgradeAndCall.selector, vaultAddress, address(newImplementation), "");

        uint256 delay = 86400;

        // Schedule upgrade
        vm.startPrank(ADMIN);
        timelock.schedule(address(proxyAdmin), 0, upgradeData, bytes32(0), bytes32(0), delay);
        vm.stopPrank();

        // solhint-disable-next-line not-rely-on-time
        uint256 timestamp = block.timestamp;

        // Wait for timelock delay
        vm.warp(timestamp + delay);

        // Execute upgrade
        vm.startPrank(ADMIN);
        timelock.execute(address(proxyAdmin), 0, upgradeData, bytes32(0), bytes32(0));
        vm.stopPrank();

        // warp back to original timestamp for oracle
        vm.warp(timestamp);

        // Verify upgrade was successful
        assertEq(
            getImplementation(vaultAddress),
            address(newImplementation),
            "Implementation address should match new implementation"
        );
    }

    function _testVaultUpgrade() internal {
        uint256 amount = 1000 ether;

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 previewWithdrawBefore = vault.previewWithdraw(amount);
        uint256 previewRedeemBefore = vault.previewRedeem(amount);
        uint256 previewDepositBefore = vault.previewDeposit(amount);
        uint256 previewMintBefore = vault.previewMint(amount);
        bool syncDepositBefore = vault.getSyncDeposit();
        bool syncWithdrawBefore = vault.getSyncWithdraw();
        address strategyGatewayBefore = vault.getStakerGateway();

        {
            uint8 decimalsBefore = vault.decimals();
            string memory nameBefore = vault.name();
            string memory symbolBefore = vault.symbol();
            address providerBefore = vault.provider();
            address[] memory assetsBefore = vault.getAssets();

            _upgradeVault();

            assertEq(vault.decimals(), decimalsBefore, "Decimals should remain unchanged");
            assertEq(vault.name(), nameBefore, "Name should remain unchanged");
            assertEq(vault.symbol(), symbolBefore, "Symbol should remain unchanged");

            assertEq(vault.provider(), providerBefore, "Provider should remain unchanged");
            assertEq(vault.getAssets(), assetsBefore, "Assets should remain unchanged");
        }

        // Verify total assets and supply remain unchanged
        assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged");
        assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");
        assertEq(vault.previewMint(amount), previewMintBefore, "Preview mint should remain unchanged");
        assertEq(vault.previewRedeem(amount), previewRedeemBefore, "Preview redeem should remain unchanged");
        assertEq(vault.previewWithdraw(amount), previewWithdrawBefore, "Preview withdraw should remain unchanged");
        assertEq(vault.previewDeposit(amount), previewDepositBefore, "Preview deposit should remain unchanged");

        assertEq(vault.getSyncDeposit(), syncDepositBefore, "SyncDeposit should remain unchanged");
        assertEq(vault.getSyncWithdraw(), syncWithdrawBefore, "SyncWithdraw should remain unchanged");

        assertEq(vault.getStakerGateway(), strategyGatewayBefore, "StrategyGateway should remain unchanged");
    }

    function _addRoleAndModifyAsset(address underlyingAsset, bool assetState) internal {
        // Grant role directly since it doesn't use timelock
        vm.startPrank(ADMIN);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), alice);
        vm.stopPrank();

        // Verify role was granted
        assertTrue(vault.hasRole(vault.ASSET_MANAGER_ROLE(), alice), "Alice should have asset manager role");

        vm.startPrank(alice);
        vault.updateAsset(1, IVault.AssetUpdateFields({active: assetState}));
        vm.stopPrank();

        // Get asset at index 1
        address assetAtIndex = vault.getAssets()[1];

        // Get asset params and verify active status
        IVault.AssetParams memory params = vault.getAsset(assetAtIndex);
        assertEq(params.active, assetState, "Asset active status should be correct");

        assertEq(assetAtIndex, underlyingAsset, "Asset at index 1 should be underlying asset");
    }

    function _addRoleAndAddFee() internal {
        // Grant roles directly since it doesn't use timelock
        vm.startPrank(ADMIN);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), alice);
        vm.stopPrank();

        assertTrue(vault.hasRole(vault.FEE_MANAGER_ROLE(), alice), "Alice should have fee manager role");

        // Set base withdrawal fee to 50 basis points (0.5%)
        uint64 newFee = 50_000; // 50_000 = 0.5% (1e8 = 100%)
        vm.startPrank(alice);
        vault.setBaseWithdrawalFee(newFee);
        vm.stopPrank();

        // Verify fee was set correctly
        assertEq(vault.baseWithdrawalFee(), newFee, "Base withdrawal fee should be set to 0.5%");
    }
}
