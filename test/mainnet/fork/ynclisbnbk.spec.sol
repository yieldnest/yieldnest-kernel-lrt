// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {BaseForkTest} from "./BaseForkTest.sol";

import {MainnetContracts} from "script/Contracts.sol";
import {MainnetKernelActors} from "script/KernelActors.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";
import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";

import {KernelClisStrategy} from "src/KernelClisStrategy.sol";

contract YnClisBNBkForkTest is BaseForkTest{
    KernelClisStrategy public strategy;
    IERC20 public wbnb;
    IERC20 public clisbnb;
    // IStakerGateway public stakerGateway;
    address public ynbnbx = address(MainnetContracts.YNBNBX);

    function setUp() public {
        // setting up vault and strategy for inherited utility functions and tests
        vault = KernelClisStrategy(payable(address(MainnetContracts.YNCLISBNBK)));
        strategy = KernelClisStrategy(payable(address(vault)));

        stakerGateway = IStakerGateway(strategy.getStakerGateway());

        asset = IERC20(MainnetContracts.WBNB);
        clisbnb = IERC20(MainnetContracts.CLISBNB);
    }

    function depositIntoVault(address depositor, uint256 depositAmount) internal override {

        // Initial balances
        uint256 ynbnbxWBNBBefore = asset.balanceOf(depositor);
        uint256 ynbnbxSharesBefore = vault.balanceOf(depositor);

        // Store initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();
        // Store initial vault WBNB balance
        uint256 vaultWBNBBefore = stakerGateway.balanceOf(address(clisbnb), address(vault));

        // Give ynbnbx some WBNB
        deal(address(asset), depositor, ynbnbxWBNBBefore + depositAmount);

        assertEq(asset.balanceOf(depositor), ynbnbxWBNBBefore + depositAmount, "WBNB balance incorrect after deal");

        vm.startPrank(depositor);
        // Approve vault to spend WBNB
        asset.approve(address(vault), depositAmount);
        // Deposit WBNB to get shares
        uint256 shares = vault.deposit(depositAmount, depositor);

        vm.stopPrank();

        // Check balances after deposit
        assertEq(asset.balanceOf(depositor), ynbnbxWBNBBefore, "WBNB balance incorrect");
        assertEq(vault.balanceOf(depositor), ynbnbxSharesBefore + shares, "Should have received shares");

        // Check vault state after deposit
        assertEq(
            vault.totalAssets(), initialTotalAssets + depositAmount, "Total assets should increase by deposit amount"
        );
        assertEq(vault.totalSupply(), initialTotalSupply + shares, "Total supply should increase by shares");

        // Check that vault clisbnb balance increased by deposit amount
        assertEq(
            stakerGateway.balanceOf(address(clisbnb), address(vault)),
            vaultWBNBBefore + depositAmount,
            "Vault balance should increase by deposit"
        );
    }

    function withdrawFromVault(address withdrawer, uint256 withdrawAmount) internal override {
        // Initial balances
        uint256 ynbnbxWBNBBefore = asset.balanceOf(withdrawer);
        uint256 ynbnbxSharesBefore = strategy.balanceOf(withdrawer);

        // Store initial state
        uint256 initialTotalAssets = strategy.totalAssets();
        uint256 initialTotalSupply = strategy.totalSupply();
        // Store initial vault WBNB balance
        uint256 vaultWBNBBefore = stakerGateway.balanceOf(address(clisbnb), address(vault));

        vm.startPrank(withdrawer);

        // Deposit WBNB to get shares
        uint256 shares = strategy.withdrawAsset(address(asset), withdrawAmount, withdrawer, withdrawer);

        vm.stopPrank();

        // Check balances after deposit
        assertEq(asset.balanceOf(withdrawer), ynbnbxWBNBBefore + withdrawAmount, "WBNB balance incorrect");
        assertEq(strategy.balanceOf(withdrawer), ynbnbxSharesBefore - shares, "Should have burnt shares");

        // Check vault state after deposit
        assertEq(
            strategy.totalAssets(), initialTotalAssets - withdrawAmount, "Total assets should decrease by withdraw amount"
        );
        assertEq(strategy.totalSupply(), initialTotalSupply - shares, "Total supply should decrease by shares");

        // Check that vault WBNB balance increased by deposit amount
        assertEq(
            stakerGateway.balanceOf(address(clisbnb), address(vault)),
            vaultWBNBBefore - withdrawAmount,
            "Vault balance should decrease by withdraw amount"
        );
    }

    function upgradeVaultWithTimelock() internal {
        KernelClisStrategy newImplementation = new KernelClisStrategy();
        _upgradeVaultWithTimelock(address(newImplementation));
    }

    function testUpgrade() public {
        bool syncDepositBefore = strategy.getSyncDeposit();
        bool syncWithdrawBefore = strategy.getSyncWithdraw();
        address strategyGatewayBefore = strategy.getStakerGateway();

        KernelClisStrategy newImplementation = new KernelClisStrategy();
        _testVaultUpgrade(address(newImplementation));

        assertEq(strategy.getSyncDeposit(), syncDepositBefore, "SyncDeposit should remain unchanged");
        assertEq(strategy.getSyncWithdraw(), syncWithdrawBefore, "SyncWithdraw should remain unchanged");

        assertEq(strategy.getStakerGateway(), strategyGatewayBefore, "StrategyGateway should remain unchanged");
        assertTrue(strategy.hasRole(strategy.ALLOCATOR_ROLE(), address(ynbnbx)), "Allocator should have role");
    }

    function testDepositBeforeUpgrade() public {
        depositIntoVault(address(ynbnbx), 1000 ether);
    }

    function testDepositAfterUpgrade() public {
        upgradeVaultWithTimelock();
        depositIntoVault(address(ynbnbx), 1000 ether);
    }

    function testWithdrawBeforeUpgrade() public {
        depositIntoVault(address(ynbnbx), 1000 ether);
        withdrawFromVault(address(ynbnbx), 100 ether);
    }

    function testWithdrawAfterUpgrade() public {
        depositIntoVault(address(ynbnbx), 1000 ether);
        upgradeVaultWithTimelock();
        withdrawFromVault(address(ynbnbx), 100 ether);
    }

    function testAddRoleAndActivateAsset() public {
        KernelClisStrategy newImplementation = new KernelClisStrategy();
        _addRoleAndModifyAsset(address(strategy), address(newImplementation), address(clisbnb), true);
    }

    function testAddRoleAndAddFee() public {
        KernelClisStrategy newImplementation = new KernelClisStrategy();
        _addRoleAndAddFee(address(strategy), address(newImplementation));
    }
}
