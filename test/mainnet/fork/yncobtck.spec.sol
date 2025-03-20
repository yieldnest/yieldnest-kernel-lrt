// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseForkTest} from "./BaseForkTest.sol";

import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {console} from "lib/forge-std/src/console.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {TokenUtils} from "test/mainnet/helpers/TokenUtils.sol";

contract YnCoBTCkForkTest is BaseForkTest {
    TokenUtils public tokenUtils;

    address public depositor = alice;

    function setUp() public {
        vault = KernelStrategy(payable(address(MainnetContracts.YNCOBTCK)));
        stakerGateway = IStakerGateway(vault.getStakerGateway());

        asset = IERC20(MainnetContracts.COBTC);
        tokenUtils = new TokenUtils(address(vault), stakerGateway);
    }

    function _upgradeVault() internal override {
        KernelStrategy newImplementation = new KernelStrategy();

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(getProxyAdmin(address(vault)));
        assertEq(proxyAdmin.owner(), 0xBEA8b88391Da9b3e8BbD007fE6cE2b9C8794320E, "Proxy admin owner should be timelock");

        // TODO: uncomment this when we have a timelock and remove repeated code
        _upgradeVaultWithTimelock(address(newImplementation));

        // Verify upgrade was successful
        assertEq(
            getImplementation(address(vault)),
            address(newImplementation),
            "Implementation address should match new implementation"
        );

        vm.stopPrank();

        // Deal asset to depositor
        deal(address(asset), depositor, 10000e8);
    }

    function testUpgrade() public {
        _testVaultUpgrade();
    }

    function testDepositBeforeUpgrade() public {
        _depositIntoVault(address(depositor), 100e8);
    }

    function testDepositAfterUpgrade() public {
        _upgradeVault();
        _depositIntoVault(address(depositor), 100e8);
    }

    function testWithdrawBeforeUpgrade() public {
        _depositIntoVault(address(depositor), 100e8);
        _withdrawFromVault(address(depositor), 50e8);
    }

    function testWithdrawAfterUpgrade() public {
        _depositIntoVault(address(depositor), 100e8);
        _upgradeVault();
        _withdrawFromVault(address(depositor), 50e8);
    }

    function testAddRoleAndAddFee() public {
        _upgradeVault();
        _addRoleAndAddFee();
    }

    function testSimpleDepositCoBTC() public {
        uint256 depositAmount = 10e8;

        // Deal coBTC to alice
        deal(address(asset), alice, depositAmount);

        // Approve the vault to spend the asset
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        uint256 totalAssetsBeforeDeposit = vault.totalAssets();
        console.log("Vault's total assets before deposit:", totalAssetsBeforeDeposit);

        // Deposit into the vault
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 aliceVaultBalance = vault.balanceOf(alice);
        console.log("Alice's vault balance after deposit:", aliceVaultBalance);

        uint256 totalAssetsAfterDeposit = vault.totalAssets();
        console.log("Vault's total assets after deposit:", totalAssetsAfterDeposit);

        // Assert that totalAssets increased by the coBTC converted to BTC
        uint256 expectedIncrease = depositAmount;
        assertEq(
            totalAssetsAfterDeposit,
            totalAssetsBeforeDeposit + expectedIncrease,
            "Vault's total assets should increase by the coBTC converted to BTC"
        );

        // // Verify the deposit was successful
        // assertEq(vault.balanceOf(alice), depositAmount, "Alice's vault balance should match the deposit amount");
        // assertEq(vault.totalAssets(), depositAmount, "Vault's total assets should match the deposit amount");

        uint256 withdrawAmount = depositAmount;

        // Check convertToAssets before withdrawal
        uint256 assetsBeforeWithdraw = vault.convertToAssets(1e18);
        // Check convertToShares before withdrawal
        uint256 sharesBeforeWithdraw = vault.convertToShares(1e18);

        // Withdraw the deposited amount
        vm.startPrank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Check convertToAssets after withdrawal
        uint256 assetsAfterWithdraw = vault.convertToAssets(1e18);
        // Check convertToShares after withdrawal
        uint256 sharesAfterWithdraw = vault.convertToShares(1e18);

        // Assert that convertToAssets after withdrawal is greater than or equal to before withdrawal
        assertTrue(
            assetsAfterWithdraw >= assetsBeforeWithdraw,
            "convertToAssets after withdrawal should be greater than or equal to before withdrawal"
        );

        // Assert that convertToShares after withdrawal is less than or equal to before withdrawal
        assertTrue(
            sharesAfterWithdraw <= sharesBeforeWithdraw,
            "convertToShares after withdrawal should be less than or equal to before withdrawal"
        );

        uint256 aliceVaultBalanceAfterWithdraw = vault.balanceOf(alice);
        console.log("Alice's vault balance after withdrawal:", aliceVaultBalanceAfterWithdraw);

        uint256 totalAssetsAfterWithdraw = vault.totalAssets();
        console.log("Vault's total assets after withdrawal:", totalAssetsAfterWithdraw);

        // Verify the withdrawal was successful
        assertApproxEqAbs(
            aliceVaultBalanceAfterWithdraw, 0, 1, "Alice's vault balance should be approximately zero after withdrawal"
        );
        //assertEq(vault.totalAssets(), 0, "Vault's total assets should be zero after withdrawal");
        uint256 aliceCoBTCBeforeRedeem = asset.balanceOf(alice);

        // Redeem the remaining shares
        vm.startPrank(alice);
        vault.redeem(aliceVaultBalanceAfterWithdraw, alice, alice);
        vm.stopPrank();

        uint256 aliceCoBTCAfterRedeem = asset.balanceOf(alice);
        uint256 coBTCDifference = aliceCoBTCAfterRedeem - aliceCoBTCBeforeRedeem;
        console.log("Alice's coBTC balance before redeem:", aliceCoBTCBeforeRedeem);
        console.log("Alice's coBTC balance after redeem:", aliceCoBTCAfterRedeem);
        console.log("Difference in coBTC that Alice has before and after redeem:", coBTCDifference);

        uint256 aliceVaultBalanceAfterRedeem = vault.balanceOf(alice);
        console.log("Alice's vault balance after redeem:", aliceVaultBalanceAfterRedeem);

        uint256 totalAssetsAfterRedeem = vault.totalAssets();
        console.log("Vault's total assets after redeem:", totalAssetsAfterRedeem);
    }
}
