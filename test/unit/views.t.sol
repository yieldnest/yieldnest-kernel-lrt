// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {SetupKernelStrategy} from "test/unit/helpers/SetupKernelStrategy.sol";

contract KernelStrategyViewUnitTest is SetupKernelStrategy {
    function setUp() public {
        deploy();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        wbnb.deposit{value: INITIAL_BALANCE}();
        wbnb.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        wbnb.approve(address(vault), type(uint256).max);
    }

    function test_KernelStrategy_asset() public view {
        address expectedAsset = MC.WBNB;
        assertEq(vault.asset(), expectedAsset, "Asset address does not match");
    }

    function test_KernelStrategy_decimals() public view {
        uint8 decimals = vault.decimals();
        assertEq(decimals, 18);
    }

    function test_KernelStrategy_getAssets() public view {
        address[] memory assets = vault.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            assertEq(vault.getAsset(asset).index, i, "Bad Index");
            assertEq(vault.getAsset(asset).decimals >= 6 || vault.getAsset(asset).decimals <= 18, true, "Bad decimals");
        }
    }

    function test_KernelStrategy_convertToShares() public view {
        uint256 amount = 1000;
        uint256 shares = vault.convertToShares(amount);
        assertEq(shares, amount, "Conversion to shares failed");
    }

    function test_KernelStrategy_convertToAssets() public view {
        uint256 shares = 1000;
        uint256 amount = vault.convertToAssets(shares);
        assertEq(amount, shares, "Conversion to assets failed");
    }

    function test_KernelStrategy_Provider() public view {
        assertEq(vault.provider(), address(provider), "Provider does not match expected");
    }

    function test_KernelStrategy_Buffer_public() public view {
        assertEq(vault.buffer(), address(0), "Buffer strategy does not match expected");
    }

    function test_KernetStrategy_GetStakerGateway() public view {
        assertEq(vault.getStakerGateway(), address(mockGateway), "Staker gateway does not match expected");
    }

    function test_KernelStrategy_GetSyncDeposit() public view {
        assertEq(vault.getSyncDeposit(), false, "SyncDeposit should be true");
    }

    function test_KernelStrategy_GetSyncWithdraw() public view {
        assertEq(vault.getSyncWithdraw(), false, "SyncWithdraw should be false");
    }
}
