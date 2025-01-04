// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {FeeMath} from "lib/yieldnest-vault/src/module/FeeMath.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";

import {SetupKernelStrategy} from "test/unit/helpers/SetupKernelStrategy.sol";

contract KernelStrategyWithdrawFeesUnitTest is SetupKernelStrategy {
    function setUp() public {
        deploy();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        wbnb.deposit{value: INITIAL_BALANCE}();
        wbnb.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.startPrank(alice);
        wbnb.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(ADMIN);
        vault.setSyncDeposit(true);
        vault.setSyncWithdraw(true);
        vault.setBaseWithdrawalFee(100_000); // Set base withdrawal fee to 0.1% (0.1% * 1e8)
        vm.stopPrank();
    }

    function test_KernelStrategy_previewRedeemWithFees(uint256 assets, uint256 withdrawnAssets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 100000);

        vm.prank(alice);
        vault.depositAsset(MC.WBNB, assets, alice);

        uint256 withdrawnShares = vault.previewDepositAsset(MC.WBNB, withdrawnAssets);
        uint256 redeemedPreview = vault.previewRedeemAsset(MC.WBNB, withdrawnShares);

        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;

        assertApproxEqRel(
            redeemedPreview, withdrawnAssets - expectedFee, 1e14, "Withdrawal fee should be 0.1% of assets"
        );
    }

    function test_KernelStrategy_previewWithdrawWithFees(uint256 assets, uint256 withdrawnAssets) external {
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 0);

        vm.prank(alice);
        vault.depositAsset(MC.WBNB, assets, alice);

        uint256 withdrawPreview = vault.previewWithdrawAsset(MC.WBNB, withdrawnAssets);

        // Base withdrawal fee is 0.1% (100_000)
        // Buffer flat fee ratio is 80% (80_000_000)
        // Vault buffer fraction is 10% (10_000_000)
        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedShares = vault.previewDepositAsset(MC.WBNB, withdrawnAssets + expectedFee);
        assertApproxEqAbs(withdrawPreview, expectedShares, 1, "Preview withdraw shares should match expected");
    }

    function test_KernelStrategy_maxRedeemWithFees(uint256 assets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);

        vm.prank(alice);
        uint256 shares = vault.depositAsset(MC.WBNB, assets, alice);

        uint256 maxShares = vault.maxRedeemAsset(MC.WBNB, alice);
        uint256 expectedAssets = vault.previewRedeemAsset(MC.WBNB, maxShares);

        uint256 convertedAssets = vault.previewMintAsset(MC.WBNB, maxShares);
        uint256 expectedFee = (expectedAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;

        vm.prank(alice);
        uint256 redeemedAmount = vault.redeemAsset(MC.WBNB, maxShares, alice, alice);

        assertApproxEqRel(redeemedAmount, expectedAssets, 1e14, "Redeemed amount should match preview");

        assertApproxEqRel(
            redeemedAmount, convertedAssets - expectedFee, 1e14, "Redeemed amount should be total assets minus fee"
        );

        assertEq(vault.balanceOf(alice), shares - maxShares, "Alice should have correct shares remaining");
    }

    function test_KernelStrategy_maxWithdrawWithFees(uint256 assets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 1000 && assets <= 100_000 ether);

        vm.prank(alice);
        vault.depositAsset(MC.WBNB, assets, alice);

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.WBNB, alice);
        uint256 previewRedeemAssets = vault.previewRedeemAsset(MC.WBNB, vault.balanceOf(alice));

        assertEq(
            maxWithdraw, previewRedeemAssets, "Max withdraw should equal previewRedeemAssets assets with full buffer"
        );

        uint256 expectedFee = (maxWithdraw * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedShares = vault.previewDepositAsset(MC.WBNB, maxWithdraw + expectedFee);

        // Verify we can actually withdraw the max amount
        vm.prank(alice);
        uint256 withdrawnShares = vault.withdrawAsset(MC.WBNB, maxWithdraw, alice, alice);

        assertApproxEqAbs(withdrawnShares, expectedShares, 2, "Withdrawn shares should match expected with fee");
        assertApproxEqAbs(vault.balanceOf(alice), 0, 1, "Alice should have no shares remaining");
    }

    function test_KernelStrategy_redeemWithFees(uint256 assets, uint256 withdrawnAssets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets / 2);
        vm.assume(withdrawnAssets > 100000);

        vm.prank(alice);
        vault.depositAsset(MC.WBNB, assets, alice);

        uint256 withdrawnShares = vault.previewDepositAsset(MC.WBNB, withdrawnAssets);

        uint256 maxRedeem = vault.maxRedeemAsset(MC.WBNB, alice);

        assertGt(maxRedeem, 0, "Max redeem should be greater than 0");
        assertLe(withdrawnShares, maxRedeem, "Withdrawn shares should be less than max redeem");

        vm.prank(alice);
        uint256 redeemedAmount = vault.redeemAsset(MC.WBNB, withdrawnShares, alice, alice);
        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        assertApproxEqRel(
            redeemedAmount, withdrawnAssets - expectedFee, 1e14, "Withdrawal fee should be 0.1% of assets"
        );
    }

    function test_KernelStrategy_withdrawWithFees(uint256 assets, uint256 withdrawnAssets) external {
        vm.assume(assets >= 100000 && assets <= 10_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 0);

        vm.prank(alice);
        vault.depositAsset(MC.WBNB, assets, alice);

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.WBNB, alice);
        if (withdrawnAssets > maxWithdraw) {
            withdrawnAssets = maxWithdraw;
        }

        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedShares = vault.previewDepositAsset(MC.WBNB, withdrawnAssets + expectedFee);

        vm.prank(alice);
        uint256 withdrawAmount = vault.withdrawAsset(MC.WBNB, withdrawnAssets, alice, alice);

        assertApproxEqAbs(withdrawAmount, expectedShares, 2, "Preview withdraw shares should match expected");
    }

    function test_KernelStrategy_feeOnRaw_FlatFee(uint256 assets) external {
        if (assets < 10) return;
        if (assets > 100_000 ether) return;

        vm.prank(alice);
        vault.depositAsset(MC.WBNB, assets, alice);

        uint256 withdrawnAssets = assets / 2;

        uint256 fee = vault._feeOnRaw(withdrawnAssets);

        // Base withdrawal fee is 0.1% (100_000)
        // Buffer flat fee ratio is 80% (80_000_000)
        // Vault buffer fraction is 10% (10_000_000)
        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        assertApproxEqAbs(fee, expectedFee, 1, "Fee should be 0.1% of assets");
    }

    function test_KernelStrategy_withdraw_success(uint256 assets) external {
        if (assets < 2) return;
        if (assets > 100_000 ether) return;

        vm.prank(alice);
        uint256 depositShares = vault.depositAsset(MC.WBNB, assets, alice);

        uint256 aliceBalanceBefore = vault.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.WBNB, alice);
        uint256 previewAmount = vault.previewWithdraw(maxWithdraw);

        uint256 expectedFee = vault._feeOnTotal(assets);

        assertEq(maxWithdraw, assets - expectedFee, "Max withdraw should be equal to assets");

        vm.prank(alice);
        uint256 shares = vault.withdrawAsset(MC.WBNB, maxWithdraw, alice, alice);
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 aliceBalanceAfter = vault.balanceOf(alice);

        assertEq(aliceBalanceBefore, aliceBalanceAfter + shares, "Alice's balance should be less the shares withdrawn");
        assertEq(previewAmount, shares, "Preview withdraw amount not preview amount");
        assertEqThreshold(depositShares, shares, 5, "Deposit shares not match with withdraw shares");
        assertLt(totalAssetsAfter, totalAssetsBefore, "Total maxWithdraw should be less after withdraw");
        assertEq(
            totalAssetsBefore,
            totalAssetsAfter + maxWithdraw,
            "Total maxWithdraw should be total assets after plus assets withdrawn"
        );
    }

    function test_KernelStrategy_maxWithdraw_sync_disabled(uint256 assets) external {
        assets = bound(assets, 2, 50_000 ether);

        vm.prank(alice);
        vault.depositAsset(MC.WBNB, assets, alice);

        // the assets are in kernel vault
        assertEq(wbnb.balanceOf(address(vault)), 0, "Vault balance should be 0");

        vm.startPrank(ADMIN);
        vault.setSyncDeposit(false);
        vault.setSyncWithdraw(false);
        vault.setBaseWithdrawalFee(1000_000); // Set base withdrawal fee to 1% (1% * 1e8)
        vm.stopPrank();

        vm.prank(alice);
        uint256 depositShares = vault.depositAsset(MC.WBNB, assets, alice);

        assertEq(vault.balanceOf(alice), depositShares * 2, "Alice should have correct shares");

        assertEq(wbnb.balanceOf(address(vault)), assets, "Vault balance should be assets");

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.WBNB, alice);
        uint256 expectedFee = vault._feeOnTotal(assets);

        assertGt(expectedFee, 0, "Fee should be greater than 0");
        assertEq(maxWithdraw, assets - expectedFee, "Max withdraw should be equal to assets");
    }

    function test_KernelStrategy_maxRedeem_sync_disabled(uint256 assets) external {
        assets = bound(assets, 2, 50_000 ether);

        vm.prank(alice);
        vault.depositAsset(MC.WBNB, assets, alice);

        // the assets are in kernel vault
        assertEq(wbnb.balanceOf(address(vault)), 0, "Vault balance should be 0");

        vm.startPrank(ADMIN);
        vault.setSyncDeposit(false);
        vault.setSyncWithdraw(false);
        vault.setBaseWithdrawalFee(1000_000); // Set base withdrawal fee to 1% (1% * 1e8)
        vm.stopPrank();

        vm.prank(alice);
        uint256 depositShares = vault.depositAsset(MC.WBNB, assets, alice);

        assertEq(vault.balanceOf(alice), depositShares * 2, "Alice should have correct shares");

        assertEq(wbnb.balanceOf(address(vault)), assets, "Vault balance should be assets");

        uint256 maxRedeem = vault.maxRedeemAsset(MC.WBNB, alice);
        uint256 expectedFee = vault._feeOnTotal(assets);

        uint256 availableShares = vault.previewDepositAsset(MC.WBNB, assets - expectedFee);

        assertGt(expectedFee, 0, "Fee should be greater than 0");
        assertEq(maxRedeem, availableShares, "Max redeem should be equal to shares");
    }
}
