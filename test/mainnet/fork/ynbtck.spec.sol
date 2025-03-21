// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MainnetContracts} from "script/Contracts.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {console} from "lib/forge-std/src/console.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {BTCRateProvider} from "src/module/BTCRateProvider.sol";
import {TokenUtils} from "test/mainnet/helpers/TokenUtils.sol";

contract YnBTCkForkTest is BaseForkTest {
    TokenUtils public tokenUtils;

    function setUp() public {
        vault = KernelStrategy(payable(address(MainnetContracts.YNBTCK)));
        stakerGateway = IStakerGateway(vault.getStakerGateway());

        asset = IERC20(MainnetContracts.BTCB);
        tokenUtils = new TokenUtils(address(vault), stakerGateway);
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

        vm.stopPrank();
    }

    function testUpgrade() public {
        _testVaultUpgrade();
    }

    function testAddRoleAndDeactivateAsset() public {
        _upgradeVault();
        _addRoleAndModifyAsset(MainnetContracts.SOLVBTC, false);
    }

    function testAddRoleAndAddFee() public {
        _upgradeVault();
        _addRoleAndAddFee();
    }

    // Use specific address for testing
    address specificUser = 0x033fDd2d046bD201d45Ea7813e75cB0c63f93AD8;

    function testWithdrawAllBTCBAfterUpgrade() public {
        _upgradeVault();

        // Set base withdrawal fee to 0
        vm.startPrank(ADMIN);
        KernelStrategy(payable(address(vault))).setBaseWithdrawalFee(0);
        vm.stopPrank();

        // Get user's share balance
        uint256 userShares = vault.balanceOf(specificUser);

        // Get the BTCB balance of the vault
        uint256 btcbBalance = stakerGateway.balanceOf(address(asset), address(vault));
        // Store total assets before withdrawal
        uint256 totalAssetsBefore = vault.totalAssets();

        // Calculate the exchange rate before withdrawal
        uint256 rateBeforeWithdraw = vault.convertToAssets(1e18);

        // Calculate shares equivalent to the BTCB balance
        uint256 sharesToBurn = vault.convertToShares(btcbBalance);

        // Withdraw based on BTCB balance of vault
        vm.startPrank(specificUser);
        uint256 sharesBurned = KernelStrategy(payable(address(vault))).withdrawAsset(
            address(asset), btcbBalance, specificUser, specificUser
        );
        vm.stopPrank();

        // Assert that the shares burned are approximately equal to the calculated shares to burn (within 1 wei)
        assertApproxEqAbs(
            sharesBurned, sharesToBurn, 1, "Shares burned should approximately match calculated shares to burn"
        );

        // Assert that the user's share balance decreased by the correct amount
        assertEq(
            vault.balanceOf(specificUser),
            userShares - sharesBurned,
            "User's share balance should decrease by shares burned"
        );

        // Calculate the exchange rate after withdrawal
        uint256 rateAfterWithdraw = vault.convertToAssets(1e18);

        // Store total assets after withdrawal
        uint256 totalAssetsAfter = vault.totalAssets();

        // Verify user has withdrawn the BTCB
        assertEq(asset.balanceOf(specificUser), btcbBalance, "User should have received the BTCB balance");

        // Verify total assets decreased by the withdrawn amount
        assertEq(totalAssetsBefore - btcbBalance, totalAssetsAfter, "Total assets should decrease by withdrawn amount");

        // Verify the exchange rate remains the same
        assertEq(rateBeforeWithdraw, rateAfterWithdraw, "Exchange rate should remain the same after withdrawal");
    }

    function testDepositSolvBTCRevertAndWithdrawAllSuccess() public {
        _upgradeVault();
        // Get the solvBTC token address
        address solvBTC = MainnetContracts.SOLVBTC;

        // Deal some solvBTC to the specificUser
        uint256 depositAmount = 1 ether;
        deal(solvBTC, specificUser, depositAmount);

        // Verify the user has the solvBTC
        assertEq(IERC20(solvBTC).balanceOf(specificUser), depositAmount, "User should have solvBTC");

        // Try to deposit solvBTC and expect a revert
        vm.startPrank(specificUser);
        IERC20(solvBTC).approve(address(vault), depositAmount);
        // Assert that solvBTC is withdrawable
        assertTrue(vault.getAssetWithdrawable(MainnetContracts.SOLVBTC), "solvBTC should be withdrawable");

        {
            // Verify that maxWithdraw for solvBTC is 0
            uint256 maxWithdrawAmount = KernelStrategy(payable(address(vault))).maxWithdrawAsset(solvBTC, specificUser);
            assertApproxEqAbs(
                maxWithdrawAmount,
                stakerGateway.balanceOf(solvBTC, address(vault)),
                1,
                "maxWithdraw for solvBTC should equal vault's staked balance"
            );
        }

        {
            // Verify that maxRedeemAsset for solvBTC is also equal to the amount
            uint256 maxRedeemShares = KernelStrategy(payable(address(vault))).maxRedeemAsset(solvBTC, specificUser);
            assertApproxEqAbs(
                vault.convertToAssets(maxRedeemShares),
                stakerGateway.balanceOf(solvBTC, address(vault)),
                1,
                "maxRedeemAsset for solvBTC should equal vault's staked balance"
            );
        }

        // The deposit should revert because solvBTC is not an accepted asset
        vm.expectRevert();
        vault.deposit(depositAmount, specificUser);
        vm.stopPrank();

        // Withdraw all solvBTC from the vault
        uint256 vaultSolvBTCBalance = stakerGateway.balanceOf(solvBTC, address(vault));

        // Check vault rate before withdrawal
        uint256 testAmount = 1e18;
        uint256 rateBeforeWithdraw = vault.convertToAssets(testAmount);

        // Calculate the expected shares based on the vault's solvBTC balance
        uint256 expectedShares = vault.previewWithdrawAsset(solvBTC, vaultSolvBTCBalance);

        vm.startPrank(specificUser);
        uint256 withdrawnShares = vault.withdrawAsset(solvBTC, vaultSolvBTCBalance, specificUser, specificUser);
        vm.stopPrank();

        // Assert that the withdrawn shares match the expected shares
        assertEq(withdrawnShares, expectedShares, "Withdrawn shares should match expected shares");

        // Check vault rate after withdrawal
        uint256 rateAfterWithdraw = vault.convertToAssets(testAmount);

        // Assert that the rate remains approximately the same
        assertApproxEqRel(
            rateBeforeWithdraw,
            rateAfterWithdraw,
            1e10,
            "Vault rate should remain approximately the same after withdrawal"
        );
        // Assert that the rate after withdrawal is greater than or equal to the rate before withdrawal
        assertTrue(
            rateAfterWithdraw >= rateBeforeWithdraw,
            "Vault rate after withdrawal should be greater than or equal to rate before withdrawal"
        );

        // Assert that the vault's solvBTC balance is now zero
        uint256 finalVaultSolvBTCBalance = stakerGateway.balanceOf(solvBTC, address(vault));
        assertEq(finalVaultSolvBTCBalance, 0, "Vault's solvBTC balance should be zero after withdrawal");
    }

    function testAssetsAfterUpgrade() public {
        _upgradeVault();
        // Disable fees for testing
        vm.startPrank(ADMIN);
        KernelStrategy(payable(address(vault))).setBaseWithdrawalFee(0);
        vm.stopPrank();

        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 8, "Should have 2 assets");
        assertEq(vault.asset(), MainnetContracts.BTCB, "Asset should be BTCB");

        address[] memory underlyingAssets = new address[](4);
        underlyingAssets[0] = MainnetContracts.BTCB;
        underlyingAssets[1] = MainnetContracts.ENZOBTC;
        underlyingAssets[2] = MainnetContracts.SOLVBTC;
        underlyingAssets[3] = MainnetContracts.SOLVBTC_BBN;

        for (uint256 i; i < underlyingAssets.length; ++i) {
            address kernelVault = stakerGateway.getVault(underlyingAssets[i]);
            uint256 assetIndex = _checkForAsset(underlyingAssets[i]);
            bool depositable = false;
            if (underlyingAssets[i] == MainnetContracts.ENZOBTC) {
                depositable = true;
            }
            uint8 decimals = 18;
            if (underlyingAssets[i] == MainnetContracts.ENZOBTC) {
                decimals = 8;
            }
            _checkAssetMetadata(underlyingAssets[i], assetIndex, decimals, depositable, true);
            uint256 kernelVaultIndex = _checkForAsset(kernelVault);
            _checkAssetMetadata(kernelVault, kernelVaultIndex, decimals, false, false);
        }
    }

    function testAddAsset() public {
        _upgradeVault();

        address newAsset = MainnetContracts.COBTC;

        vm.expectRevert();
        vault.addAsset(newAsset, true);

        vm.startPrank(ADMIN);
        vault.addAsset(newAsset, true);
        vm.stopPrank();

        assertEq(vault.getAssets().length, 9, "Should have 9 assets");

        uint256 index = _checkForAsset(newAsset);
        _checkAssetMetadata(newAsset, index, 8, true, false);
    }

    function testAddAssetWithDecimals() public {
        _upgradeVault();

        address newAsset = MainnetContracts.COBTC;

        vm.expectRevert();
        vault.addAssetWithDecimals(newAsset, 8, true);

        vm.startPrank(ADMIN);
        vault.addAssetWithDecimals(newAsset, 8, true);
        vm.stopPrank();

        assertEq(vault.getAssets().length, 9, "Should have 3 assets");

        uint256 index = _checkForAsset(newAsset);
        _checkAssetMetadata(newAsset, index, 8, true, true);
    }

    function testAddAssetWithDepositableAndWithdrawable() public {
        _upgradeVault();

        address newAsset = MainnetContracts.COBTC;

        vm.expectRevert();
        vault.addAssetWithDecimals(newAsset, 8, true, false);

        vm.startPrank(ADMIN);
        vault.addAssetWithDecimals(newAsset, 8, true, false);
        vm.stopPrank();

        assertEq(vault.getAssets().length, 9, "Should have 9 assets");

        uint256 index = _checkForAsset(newAsset);
        _checkAssetMetadata(newAsset, index, 8, true, false);

        vm.startPrank(ADMIN);
        vault.setAssetWithdrawable(newAsset, true);
        vm.stopPrank();

        _checkAssetMetadata(newAsset, index, 8, true, true);

        // Test setting asset to not withdrawable
        vm.startPrank(ADMIN);
        vault.setAssetWithdrawable(newAsset, false);
        vm.stopPrank();

        _checkAssetMetadata(newAsset, index, 8, true, false);
    }

    function testWithdrawAllSolvBTC() public {
        _upgradeVault();

        uint256 balance = stakerGateway.balanceOf(MainnetContracts.SOLVBTC, address(vault));

        // Check rate before withdrawal
        uint256 rateBeforeWithdraw = vault.convertToAssets(1e18);
        uint256 sharesBeforeWithdraw = vault.convertToShares(1e18);

        _withdrawFromVault(MainnetContracts.SOLVBTC, specificUser, balance);

        // Check rate after withdrawal and assert it stayed the same
        uint256 rateAfterWithdraw = vault.convertToAssets(1e18);
        uint256 sharesAfterWithdraw = vault.convertToShares(1e18);

        // Assert that convertToShares stays the same
        assertApproxEqRel(
            sharesBeforeWithdraw,
            sharesAfterWithdraw,
            1e12,
            "Shares conversion rate should remain approximately the same"
        );
        assertTrue(sharesAfterWithdraw <= sharesBeforeWithdraw, "Shares after withdrawal should not increase");
        assertApproxEqRel(
            rateBeforeWithdraw,
            rateAfterWithdraw,
            1e10,
            "Exchange rate should remain approximately the same after withdrawal"
        );
        assertTrue(rateAfterWithdraw >= rateBeforeWithdraw, "Exchange rate should not decrease after withdrawal");

        assertEq(stakerGateway.balanceOf(MainnetContracts.SOLVBTC, address(vault)), 0, "Should have 0 balance");
    }

    function testWithdrawAllSolvBTCBBN() public {
        _upgradeVault();

        uint256 balance = stakerGateway.balanceOf(MainnetContracts.SOLVBTC_BBN, address(vault));
        // Check rate before withdrawal
        uint256 rateBeforeWithdraw = vault.convertToAssets(1e18);

        _withdrawFromVault(MainnetContracts.SOLVBTC_BBN, specificUser, balance);

        // Check rate after withdrawal and assert it stayed the same
        uint256 rateAfterWithdraw = vault.convertToAssets(1e18);
        assertEq(rateBeforeWithdraw, rateAfterWithdraw, "Exchange rate should remain the same after withdrawal");

        assertEq(stakerGateway.balanceOf(MainnetContracts.SOLVBTC_BBN, address(vault)), 0, "Should have 0 balance");
    }

    function _checkForAsset(address assetAddress) internal view returns (uint256 index) {
        address[] memory assets = vault.getAssets();
        bool isIncluded = false;

        for (uint256 i; i < assets.length;) {
            if (assets[i] == assetAddress) {
                isIncluded = true;
                index = i;
                break;
            }
            {
                i++;
            }
        }

        assertTrue(isIncluded, "Asset should be included");
    }

    function _checkAssetMetadata(
        address assetAddress,
        uint256 index,
        uint8 decimals,
        bool depositable,
        bool withdrawable
    ) internal view {
        IVault.AssetParams memory params = vault.getAsset(assetAddress);

        assertEq(params.index, index, "Asset index should be correct");
        assertEq(params.decimals, decimals, "Asset decimals should be correct");
        assertEq(params.active, depositable, "Asset depositable should be correct");
        assertEq(vault.getAssetWithdrawable(assetAddress), withdrawable, "Asset withdrawable should be correct");
    }

    function testDepositAndRedeemEnzoBTC() public {
        _upgradeVault();

        // Get initial balances
        uint256 initialVaultBalance = stakerGateway.balanceOf(MainnetContracts.ENZOBTC, address(vault));

        // Get some enzoBTC for testing
        uint256 depositAmount = 1000 ether;
        depositAmount = tokenUtils.getEnzoBTC(alice, depositAmount);

        // Check rate before deposit
        uint256 rateBeforeDeposit = vault.convertToAssets(1e18);

        // Approve and deposit
        vm.startPrank(alice);
        IERC20(MainnetContracts.ENZOBTC).approve(address(vault), depositAmount);
        uint256 shares = vault.depositAsset(MainnetContracts.ENZOBTC, depositAmount, alice);
        vm.stopPrank();

        // Check rate after deposit
        uint256 rateAfterDeposit = vault.convertToAssets(1e18);

        // Assert that the rate remains the same
        assertEq(rateBeforeDeposit, rateAfterDeposit, "Exchange rate should remain the same after deposit");

        // Verify deposit was successful
        uint256 finalVaultBalance = stakerGateway.balanceOf(MainnetContracts.ENZOBTC, address(vault));
        assertEq(
            finalVaultBalance, initialVaultBalance + depositAmount, "Vault should have received the deposited enzoBTC"
        );

        // Check rate before redemption
        uint256 rateBeforeRedeem = vault.convertToAssets(1e18);
        // Calculate shares to assets conversion before redemption
        uint256 sharesConversionBefore = vault.convertToShares(1e18);

        // Redeem all shares
        vm.startPrank(alice);
        uint256 redeemedAmount = vault.redeemAsset(MainnetContracts.ENZOBTC, shares, alice, alice);
        vm.stopPrank();

        // Check rate after redemption
        uint256 rateAfterRedeem = vault.convertToAssets(1e18);

        // Check shares conversion after redemption
        uint256 sharesConversionAfter = vault.convertToShares(1e18);

        // Assert that the shares conversion decreased
        assertApproxEqRel(
            sharesConversionBefore,
            sharesConversionAfter,
            1e8,
            "Shares conversion should be approximately equal after redemption"
        );
        assertTrue(sharesConversionAfter < sharesConversionBefore, "Shares conversion should be lower after redemption");
        assertApproxEqRel(
            rateBeforeRedeem,
            rateAfterRedeem,
            1e8,
            "Exchange rate should remain approximately the same after redemption"
        );
        // Assert that the rate after redemption is greater than or equal to the rate before redemption
        // This verifies that redemption doesn't decrease the exchange rate and potentially increases it
        assertTrue(
            rateAfterRedeem >= rateBeforeRedeem,
            "Exchange rate after redemption should be greater than or equal to rate before redemption"
        );

        // Assert that the redeemed amount matches the deposit amount
        assertApproxEqAbs(
            redeemedAmount,
            depositAmount,
            1, // Small threshold for potential rounding errors
            "Redeemed amount should match the deposit amount"
        );
    }

    function testDepositAndWithdrawEnzoBTC() public {
        _upgradeVault();

        // Get initial balances
        uint256 initialVaultBalance = stakerGateway.balanceOf(MainnetContracts.ENZOBTC, address(vault));

        // Get some enzoBTC for testing
        uint256 depositAmount = 1000 ether;
        depositAmount = tokenUtils.getEnzoBTC(alice, depositAmount);

        // Check rate before deposit
        uint256 rateBeforeDeposit = vault.convertToAssets(1e18);

        // Approve and deposit
        vm.startPrank(alice);
        IERC20(MainnetContracts.ENZOBTC).approve(address(vault), depositAmount);
        uint256 shares = vault.depositAsset(MainnetContracts.ENZOBTC, depositAmount, alice);
        vm.stopPrank();

        // Check rate after deposit
        uint256 rateAfterDeposit = vault.convertToAssets(1e18);

        // Assert that the rate remains the same
        assertEq(rateBeforeDeposit, rateAfterDeposit, "Exchange rate should remain the same after deposit");

        // Verify deposit was successful
        uint256 finalVaultBalance = stakerGateway.balanceOf(MainnetContracts.ENZOBTC, address(vault));
        assertEq(
            finalVaultBalance, initialVaultBalance + depositAmount, "Vault should have received the deposited enzoBTC"
        );

        // Check rate before redemption
        uint256 rateBeforeRedeem = vault.convertToAssets(1e18);
        // Calculate shares to assets conversion before redemption
        uint256 sharesConversionBefore = vault.convertToShares(1e18);

        // Withdraw using withdrawAsset instead of redeemAsset
        vm.startPrank(alice);
        uint256 redeemedAmount = vault.previewRedeemAsset(MainnetContracts.ENZOBTC, shares);
        vault.withdrawAsset(MainnetContracts.ENZOBTC, redeemedAmount, alice, alice);
        vm.stopPrank();

        // Check rate after redemption
        uint256 rateAfterRedeem = vault.convertToAssets(1e18);

        // Check shares conversion after redemption
        uint256 sharesConversionAfter = vault.convertToShares(1e18);

        // Assert that the shares conversion decreased
        assertApproxEqRel(
            sharesConversionBefore,
            sharesConversionAfter,
            1e8,
            "Shares conversion should be approximately equal after redemption"
        );

        assertTrue(
            sharesConversionAfter <= sharesConversionBefore, "Shares conversion should be lower after redemption"
        );
        assertApproxEqRel(
            rateBeforeRedeem,
            rateAfterRedeem,
            1e8,
            "Exchange rate should remain approximately the same after redemption"
        );
        // Assert that the rate after redemption is greater than or equal to the rate before redemption
        // This verifies that redemption doesn't decrease the exchange rate and potentially increases it
        assertTrue(
            rateAfterRedeem >= rateBeforeRedeem,
            "Exchange rate after redemption should be greater than or equal to rate before redemption"
        );

        // Assert that the redeemed amount matches the deposit amount
        assertApproxEqAbs(
            redeemedAmount,
            depositAmount,
            1, // Small threshold for potential rounding errors
            "Redeemed amount should match the deposit amount"
        );
    }
}
