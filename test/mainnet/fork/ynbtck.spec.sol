// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MainnetContracts} from "script/Contracts.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";
import {BTCRateProvider} from "src/module/BTCRateProvider.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {console} from "lib/forge-std/src/console.sol";


import {KernelStrategy} from "src/KernelStrategy.sol";

contract YnBTCkForkTest is BaseForkTest {
    function setUp() public {
        vault = KernelStrategy(payable(address(MainnetContracts.YNBTCK)));
        stakerGateway = IStakerGateway(vault.getStakerGateway());

        asset = IERC20(MainnetContracts.BTCB);
    }

    function _upgradeVault() internal override {
        KernelStrategy newImplementation = new KernelStrategy();

        // TODO: uncomment this when we have a timelock and remove repeated code
        // _upgradeVaultWithTimelock(address(newImplementation));

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(getProxyAdmin(address(vault)));

        assertEq(proxyAdmin.owner(), ADMIN, "Proxy admin owner should be admin");

        vm.startPrank(ADMIN);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(payable(address(vault))), address(newImplementation), "");
        vm.stopPrank();

        // Verify upgrade was successful
        assertEq(
            getImplementation(address(vault)),
            address(newImplementation),
            "Implementation address should match new implementation"
        );
    }

    function testUpgrade() public {
        _testVaultUpgrade();
    }

    function testDepositBeforeUpgrade() public {
        _depositIntoVault(alice, 100 ether);
    }

    function testDepositAfterUpgrade() public {
        _upgradeVault();
        _depositIntoVault(alice, 100 ether);
    }

    function testWithdrawBeforeUpgrade() public {
        _depositIntoVault(alice, 100 ether);
        _withdrawFromVault(alice, 50 ether);
    }

    function testWithdrawAfterUpgrade() public {
        _depositIntoVault(alice, 100 ether);
        _upgradeVault();
        _withdrawFromVault(alice, 50 ether);
    }

    function testAddRoleAndDeactivateAsset() public {
        _upgradeVault();
        _addRoleAndModifyAsset(MainnetContracts.SOLVBTC, false);
    }

    function testAddRoleAndAddFee() public {
        _upgradeVault();
        _addRoleAndAddFee();
    }

    function testAddEnzoBTC() public {
        // _upgradeVault();
        _addEnzoBTC();
    }

    function _addEnzoBTC() internal {

        address TIMELOCK = 0xE698E3c74917C2bF80E63366673179293E4AB856;
        vm.startPrank(TIMELOCK);

        // Deploy and set provider
        address provider = 0x75D4d5C7633a0fD0acB2A2dC07F3eaa068c1a798; // address(new BTCRateProvider());

        vault.setProvider(provider);

        address enzoBTCVault = IStakerGateway(MainnetContracts.STAKER_GATEWAY).getVault(MainnetContracts.ENZOBTC);
        // Get initial rate before adding assets
        uint256 initialRate = vault.convertToAssets(1e18);

        // Add asset
        vault.addAsset(MainnetContracts.ENZOBTC, true);
        vault.addAssetWithDecimals(enzoBTCVault, 8, false);

        vm.stopPrank();
        // Verify asset was added
        assertTrue( vault.getAsset(MainnetContracts.ENZOBTC).active, "enzoBTC should be active");
        assertEq( vault.getAsset(MainnetContracts.ENZOBTC).decimals, 8, "enzoBTC should have 8 decimals");
        assertEq( vault.getAsset(enzoBTCVault).decimals, 8, "enzoBTC should have 8 decimals");
        assertEq( vault.getAsset(enzoBTCVault).active, false, "enzoBTC should not be active");

        // Verify rate after adding assets
        assertEq(vault.convertToAssets(1e18), initialRate, "Rate should not change after adding assets");

        {
            // Test that preview deposit returns same shares for equivalent amounts
            uint256 btcbAmount = 1000 ether; // 1000 BTCB in 18 decimals
            uint256 enzoAmount = 1000 * 1e8; // 1000 enzoBTC in 8 decimals

            uint256 btcbShares = vault.previewDepositAsset(MainnetContracts.BTCB, btcbAmount);
            uint256 enzoShares = vault.previewDepositAsset(MainnetContracts.ENZOBTC, enzoAmount);

            console.log("BTCB - Amount: %s, Shares: %s", btcbAmount, btcbShares);
            console.log("Enzo - Amount: %s, Shares: %s", enzoAmount, enzoShares);

            assertEq(btcbShares, enzoShares, "Preview deposit shares should be equal for equivalent amounts");
        }

        // Impersonate enzoBTC whale
        address ENZO_WHALE = 0x16b9CA0A8f5b90a531286E2886BAc5e1A19072E3;
        vm.startPrank(ENZO_WHALE);

        uint256 amount = 10 * 1e8; // 100 enzoBTC (8 decimals)
        uint256 expectedTVLIncrease = 10 ether; // Expected 18 decimal increase

        uint256 beforeTVL = vault.totalAssets();

        IERC20(MainnetContracts.ENZOBTC).approve(address(vault), amount);
        vault.depositAsset(MainnetContracts.ENZOBTC, amount, ENZO_WHALE);

        assertEq(
            IERC20(MainnetContracts.ENZOBTC).balanceOf(address(vault)),
            0,
            "Vault should have received enzoBTC"
        );

        uint256 afterTVL = vault.totalAssets();
        assertEq(afterTVL - beforeTVL, expectedTVLIncrease, "TVL should increase by 100 ether");

        // Verify rate after deposit
        assertEq(vault.convertToAssets(1e18), initialRate, "Rate should not change after deposit");

        uint256 withdrawSharesAmount = vault.balanceOf(ENZO_WHALE) / 4;


        {
            uint256 withdrawAmount = (amount / 4) * 999 / 1000; // 2.5 * 1e8 enzoBTC with 0.1% fee
            uint256 expectedTVLDecrease = (2.5 ether * 999) / 1000; // Expected 18 decimal decrease with 0.1% fee

            beforeTVL = vault.totalAssets();
            uint256 beforeWhaleBalance = IERC20(MainnetContracts.ENZOBTC).balanceOf(ENZO_WHALE);

            vault.redeemAsset(MainnetContracts.ENZOBTC, withdrawSharesAmount, ENZO_WHALE, ENZO_WHALE);

            afterTVL = vault.totalAssets();
            uint256 afterWhaleBalance = IERC20(MainnetContracts.ENZOBTC).balanceOf(ENZO_WHALE);

            assertApproxEqRel(beforeTVL - afterTVL, expectedTVLDecrease, 1e13, "TVL should decrease by expectedTVLDecrease");
            assertApproxEqRel(
                afterWhaleBalance - beforeWhaleBalance,
                withdrawAmount,
                1e13,
                "Whale should have received enzoBTC back minus withdrawal fee"
            );
        }

        // Verify rate after withdraw due to the fee
        assertGe(vault.convertToAssets(1e18), initialRate, "Rate should not decrease after withdraw");

        {
            uint256 withdrawAmount = amount / 4; // 2.5 * 1e8 enzoBTC
            uint256 expectedTVLDecrease = 2.5 ether; // Expected 18 decimal decrease

            beforeTVL = vault.totalAssets();
            uint256 beforeWhaleBalance = IERC20(MainnetContracts.ENZOBTC).balanceOf(ENZO_WHALE);

            vault.withdrawAsset(MainnetContracts.ENZOBTC, withdrawAmount, ENZO_WHALE, ENZO_WHALE);

            afterTVL = vault.totalAssets();
            uint256 afterWhaleBalance = IERC20(MainnetContracts.ENZOBTC).balanceOf(ENZO_WHALE);

            assertEq(beforeTVL - afterTVL, expectedTVLDecrease, "TVL should decrease by expectedTVLDecrease");
            assertEq(
                afterWhaleBalance - beforeWhaleBalance,
                withdrawAmount,
                "Whale should have received exact amount of enzoBTC"
            );
        }

        {
            uint256 donationAmount = 1e8; // 1 enzoBTC
            uint256 expectedTVLIncrease = 1 ether; // 1e18 for accounting

            beforeTVL = vault.totalAssets();
            uint256 beforeVaultBalance = IERC20(MainnetContracts.ENZOBTC).balanceOf(address(vault));
            uint256 beforeRate = vault.convertToAssets(1e18);

            // Transfer enzoBTC directly to vault as donation
            IERC20(MainnetContracts.ENZOBTC).transfer(address(vault), donationAmount);

            afterTVL = vault.totalAssets();
            uint256 afterVaultBalance = IERC20(MainnetContracts.ENZOBTC).balanceOf(address(vault));
            uint256 afterRate = vault.convertToAssets(1e18);

            assertEq(afterTVL - beforeTVL, expectedTVLIncrease, "TVL should increase by donation amount");
            assertEq(afterVaultBalance - beforeVaultBalance, donationAmount, "Vault balance should increase by donation");
            assertGt(afterRate, beforeRate, "Rate should increase after donation");
        }

        vm.stopPrank();
    }
}
