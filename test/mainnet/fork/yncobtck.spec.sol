// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {MainnetKernelActors} from "script/KernelActors.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";
import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";

import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {TokenUtils} from "test/mainnet/helpers/TokenUtils.sol";
import {console} from "lib/forge-std/src/console.sol";


contract BaseForkTest is Test, MainnetKernelActors, ProxyUtils {
    TokenUtils public tokenUtils;
    KernelStrategy public vault;
    IStakerGateway public stakerGateway;
    IERC20 public asset;
    address public alice = 0x1234567890AbcdEF1234567890aBcdef12345678;

    function setUp() public {
        vault = KernelStrategy(payable(address(MainnetContracts.YNCOBTCK)));
        stakerGateway = IStakerGateway(vault.getStakerGateway());

        asset = IERC20(MainnetContracts.COBTC);
        tokenUtils = new TokenUtils(address(vault), stakerGateway);
    }
    function testSimpleDepositCoBTC() public {
        uint256 depositAmount = 10e8;

        // Deal coBTC to alice
        deal(address(asset), alice, depositAmount);

        // Approve the vault to spend the asset
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);

        // Deposit into the vault
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 aliceVaultBalance = vault.balanceOf(alice);
        console.log("Alice's vault balance after deposit:", aliceVaultBalance);

        uint256 totalAssetsAfterDeposit = vault.totalAssets();
        console.log("Vault's total assets after deposit:", totalAssetsAfterDeposit);

        // // Verify the deposit was successful
        // assertEq(vault.balanceOf(alice), depositAmount, "Alice's vault balance should match the deposit amount");
        // assertEq(vault.totalAssets(), depositAmount, "Vault's total assets should match the deposit amount");

        uint256 withdrawAmount = depositAmount - 1;

        // Withdraw the deposited amount
        vm.startPrank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        uint256 aliceVaultBalanceAfterWithdraw = vault.balanceOf(alice);
        console.log("Alice's vault balance after withdrawal:", aliceVaultBalanceAfterWithdraw);

        uint256 totalAssetsAfterWithdraw = vault.totalAssets();
        console.log("Vault's total assets after withdrawal:", totalAssetsAfterWithdraw);

        // Verify the withdrawal was successful
        assertApproxEqAbs(aliceVaultBalanceAfterWithdraw, 0, 1e10, "Alice's vault balance should be approximately zero after withdrawal");
        //assertEq(vault.totalAssets(), 0, "Vault's total assets should be zero after withdrawal");
    }

    // function testSimpleWithdraw() public {
    //     uint256 depositAmount = 100 ether;
    //     uint256 withdrawAmount = 50 ether;

    //     // Approve the vault to spend the asset
    //     vm.startPrank(alice);
    //     asset.approve(address(vault), depositAmount);

    //     // Deposit into the vault
    //     vault.deposit(depositAmount, alice);

    //     // Withdraw from the vault
    //     vault.withdraw(withdrawAmount, alice, alice);
    //     vm.stopPrank();

    //     // Verify the withdrawal was successful
    //     assertEq(vault.balanceOf(alice), depositAmount - withdrawAmount, "Alice's vault balance should match the remaining amount");
    //     assertEq(vault.totalAssets(), depositAmount - withdrawAmount, "Vault's total assets should match the remaining amount");
    // }
}