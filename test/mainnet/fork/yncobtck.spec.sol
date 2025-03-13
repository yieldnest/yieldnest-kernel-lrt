// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MainnetContracts} from "script/Contracts.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {CoBTCRateProvider} from "src/module/CoBTCRateProvider.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";

import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";

contract YnBTCkForkTest is BaseForkTest {
    function setUp() public {
        vault = KernelStrategy(payable(address(MainnetContracts.YNCOBTCK)));
        stakerGateway = IStakerGateway(vault.getStakerGateway());

        asset = IERC20(MainnetContracts.COBTC);

        assertEq(vault.asset(), address(asset), "Asset should be set");
        assertEq(vault.baseWithdrawalFee(), 0, "Base withdrawal fee should be zero");
        assertTrue(vault.getSyncDeposit(), "Sync deposit should be enabled");
        assertTrue(vault.getSyncWithdraw(), "Sync withdraw should be enabled");
    }

    function _changeRateProvider() internal {
        address vaultAddress = address(vault);

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(getProxyAdmin(vaultAddress));

        TimelockController timelock = TimelockController(payable(proxyAdmin.owner()));

        // test PROVIDER_MANAGER role
        assertTrue(
            vault.hasRole(vault.PROVIDER_MANAGER_ROLE(), address(timelock)), "Provider manager role should exist"
        );

        CoBTCRateProvider newRateProvider = new CoBTCRateProvider();

        bytes memory setProviderData = abi.encodeWithSelector(vault.setProvider.selector, address(newRateProvider));

        uint256 delay = 86400;

        // Schedule setProvider
        vm.startPrank(ADMIN);
        timelock.schedule(address(vault), 0, setProviderData, bytes32(0), bytes32(0), delay);
        vm.stopPrank();

        // solhint-disable-next-line not-rely-on-time
        uint256 timestamp = block.timestamp;

        // Wait for timelock delay
        vm.warp(timestamp + delay);

        // Execute setProvider
        vm.startPrank(ADMIN);
        timelock.execute(address(vault), 0, setProviderData, bytes32(0), bytes32(0));
        vm.stopPrank();

        // warp back to original timestamp for oracle
        vm.warp(timestamp);

        assertEq(vault.provider(), address(newRateProvider), "Rate provider should be updated");
    }

    function testProviderChange() public {
        uint256 assets = 1e10; // 100 bitcoin
        uint256 shares = 1e20; // 100 ether

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 previewWithdrawBefore = vault.previewWithdraw(assets);
        uint256 previewDepositBefore = vault.previewDeposit(assets);
        uint256 previewRedeemBefore = vault.previewRedeem(shares);
        uint256 previewMintBefore = vault.previewMint(shares);
        uint256 convertedAssetsBefore = vault.convertToAssets(shares);
        uint256 convertedSharesBefore = vault.convertToShares(assets);

        _changeRateProvider();

        assertEq(vault.totalAssets(), totalAssetsBefore / 1e10, "Total assets should change only in decimals");
        assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");

        uint256 threshold = 5e12;
        // 5e12 / 1e18 = 5e-6;
        // 5e-6 * 1e10 = 5e4;
        // 5e4 satoshi in usd ~ 40 usd at 80k usd/btc
        // i.e. there is a $40 change for 100 bitcoin

        assertApproxEqRel(
            vault.convertToAssets(shares), convertedAssetsBefore, threshold, "Converted assets should remain unchanged"
        );
        assertApproxEqRel(
            vault.convertToShares(assets), convertedSharesBefore, threshold, "Converted shares should remain unchanged"
        );

        assertApproxEqRel(
            vault.previewDeposit(assets), previewDepositBefore, threshold, "Preview deposit should remain unchanged"
        );
        assertApproxEqRel(
            vault.previewWithdraw(assets), previewWithdrawBefore, threshold, "Preview withdraw should remain unchanged"
        );

        assertApproxEqRel(
            vault.previewMint(shares), previewMintBefore, threshold, "Preview mint should remain unchanged"
        );
        assertApproxEqRel(
            vault.previewRedeem(shares), previewRedeemBefore, threshold, "Preview redeem should remain unchanged"
        );
    }

    function _depositIntoVault_BeforeProviderChange(address depositor, uint256 depositAmount) internal virtual {
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
            vault.totalAssets(),
            initialTotalAssets + depositAmount * 1e10,
            "Total assets should increase by deposit amount scaled up"
        );
        assertEq(vault.totalSupply(), initialTotalSupply + shares, "Total supply should increase by shares");

        // Check that vault Asset balance increased by deposit amount
        assertEq(_getStakedBalance(), vaultAssetBefore + depositAmount, "Vault balance should increase by deposit");
    }

    function testDeposit_BeforeProviderChange() public {
        uint256 amount = 1e10; // 100 bitcoin
        _depositIntoVault_BeforeProviderChange(alice, amount);
    }

    function testDeposit_AfterProviderChange() public {
        uint256 amount = 1e10; // 100 bitcoin
        _changeRateProvider();
        _depositIntoVault(alice, amount);
    }

    function testWithdraw_WithDepositBeforeProviderChange() public {
        uint256 amount = 1e10; // 100 bitcoin
        _depositIntoVault_BeforeProviderChange(alice, amount);
        _changeRateProvider();
        _withdrawFromVault(alice, amount / 2);
    }

    function testWithdraw_AfterProviderChange() public {
        uint256 amount = 1e10; // 100 bitcoin
        _changeRateProvider();
        _depositIntoVault(alice, amount);
        _withdrawFromVault(alice, amount / 2);
    }
}
