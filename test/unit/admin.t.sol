// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {SetupKernelStrategy} from "test/unit/helpers/SetupKernelStrategy.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";

contract KernelStrategyAdminUintTest is SetupKernelStrategy {
    MockERC20 public asset;

    function setUp() public {
        deploy();
        asset = new MockERC20("Mock Token", "MOCK", 18);

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        wbnb.deposit{value: INITIAL_BALANCE}();
        wbnb.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        wbnb.approve(address(vault), type(uint256).max);

        vm.startPrank(ADMIN);
        vault.grantRole(vault.KERNEL_DEPENDENCY_MANAGER_ROLE(), KERNEL_DEPENDENCY_MANAGER);
        vault.grantRole(vault.DEPOSIT_MANAGER_ROLE(), DEPOSIT_MANAGER);
        vault.grantRole(vault.ALLOCATOR_MANAGER_ROLE(), ALLOCATOR_MANAGER);
        vm.stopPrank();
    }

    function test_Vault_setStakerGateway() public {
        address sg = address(200);
        vm.prank(KERNEL_DEPENDENCY_MANAGER);
        vault.setStakerGateway(sg);
        assertEq(vault.getStakerGateway(), sg);
    }

    function test_Vault_setStakerGateway_nullAddress() public {
        vm.prank(KERNEL_DEPENDENCY_MANAGER);
        vm.expectRevert();
        vault.setStakerGateway(address(0));
    }

    function test_Vault_setStakerGateway_unauthorized() public {
        address sg = address(200);
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        vault.setStakerGateway(sg);
    }

    function test_Vault_setSyncDeposit() public {
        vm.prank(DEPOSIT_MANAGER);
        vault.setSyncDeposit(true);
        assertEq(vault.getSyncDeposit(), true);

        vm.prank(DEPOSIT_MANAGER);
        vault.setSyncDeposit(false);
        assertEq(vault.getSyncDeposit(), false);
    }

    function test_Vault_setSyncDeposit_unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        vault.setSyncDeposit(true);
    }

    function test_Vault_setSyncWithdraw() public {
        vm.prank(DEPOSIT_MANAGER);
        vault.setSyncWithdraw(true);
        assertEq(vault.getSyncWithdraw(), true);

        vm.prank(DEPOSIT_MANAGER);
        vault.setSyncWithdraw(false);
        assertEq(vault.getSyncWithdraw(), false);
    }

    function test_Vault_setSyncWithdraw_unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        vault.setSyncWithdraw(true);
    }

    function test_Vault_setHasAllocator() public {
        vm.prank(ALLOCATOR_MANAGER);
        vault.setHasAllocator(true);
        assertEq(vault.getHasAllocator(), true);

        vm.prank(ALLOCATOR_MANAGER);
        vault.setHasAllocator(false);
        assertEq(vault.getHasAllocator(), false);
    }

    function test_Vault_setHasAllocator_unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        vault.setHasAllocator(true);
    }

    function test_Vault_setAssetWithdrawable() public {
        vm.prank(ASSET_MANAGER);
        vault.addAsset(address(asset), true);

        assertEq(vault.getAssetWithdrawable(address(asset)), false, "asset should not be withdrawable");

        vm.prank(ASSET_MANAGER);
        vault.setAssetWithdrawable(address(asset), true);

        assertEq(vault.getAssetWithdrawable(address(asset)), true, "asset should be withdrawable");

        vm.prank(ASSET_MANAGER);
        vault.setAssetWithdrawable(address(asset), false);

        assertEq(vault.getAssetWithdrawable(address(asset)), false, "asset should not be withdrawable");
    }

    function test_Vault_setAssetWithdrawable_unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        vault.setAssetWithdrawable(address(asset), true);
    }

    function test_Vault_addAsset_Depositable_NotWithdrawable() public {
        MockERC20 asset2 = new MockERC20("Mock Token 2", "MOCK2", 12);
        vm.prank(ASSET_MANAGER);
        vault.addAssetWithDecimals(address(asset2), 12, true, false);

        assertEq(vault.getAsset(address(asset2)).active, true, "asset2 should be active");
        assertEq(vault.getAsset(address(asset2)).decimals, 12, "asset2 should have 10 decimals");
        assertEq(vault.getAssetWithdrawable(address(asset2)), false, "asset2 should not be withdrawable");

        MockERC20 asset3 = new MockERC20("Mock Token 3", "MOCK3", 10);
        vm.prank(ASSET_MANAGER);
        vault.addAsset(address(asset3), true);

        assertEq(vault.getAsset(address(asset3)).active, true, "asset2 should be active");
        assertEq(vault.getAsset(address(asset3)).decimals, 10, "asset2 should have 10 decimals");
        assertEq(vault.getAssetWithdrawable(address(asset3)), false, "asset2 should not be withdrawable");
    }

    function test_Vault_addAsset_Depositable_Withdrawable() public {
        vm.prank(ASSET_MANAGER);
        vault.addAssetWithDecimals(address(asset), 18, true);

        assertEq(vault.getAsset(address(asset)).active, true);
        assertEq(vault.getAsset(address(asset)).decimals, 18, "asset should have 18 decimals");
        assertEq(vault.getAssetWithdrawable(address(asset)), true, "asset should not be withdrawable");
    }

    function test_Vault_addAsset_NotDepositable_NotWithdrawable() public {
        vm.prank(ASSET_MANAGER);
        vault.addAsset(address(asset), false);
        assertEq(vault.getAsset(address(asset)).active, false);
        assertEq(vault.getAsset(address(asset)).decimals, 18, "asset should have 18 decimals");
        assertEq(vault.getAssetWithdrawable(address(asset)), false, "asset should not be withdrawable");

        MockERC20 asset2 = new MockERC20("Mock Token 2", "MOCK2", 12);
        vm.prank(ASSET_MANAGER);
        vault.addAssetWithDecimals(address(asset2), 12, false, false);

        assertEq(vault.getAsset(address(asset2)).active, false, "asset2 should not be active");
        assertEq(vault.getAsset(address(asset2)).decimals, 12, "asset2 should have 10 decimals");
        assertEq(vault.getAssetWithdrawable(address(asset2)), false, "asset2 should not be withdrawable");

        MockERC20 asset3 = new MockERC20("Mock Token 3", "MOCK3", 10);
        vm.prank(ASSET_MANAGER);
        vault.addAsset(address(asset3), false);

        assertEq(vault.getAsset(address(asset3)).active, false, "asset2 should not be active");
        assertEq(vault.getAsset(address(asset3)).decimals, 10, "asset2 should have 10 decimals");
        assertEq(vault.getAssetWithdrawable(address(asset3)), false, "asset2 should not be withdrawable");
    }

    function test_Vault_addAsset_NotDepositable_Withdrawable() public {
        MockERC20 asset2 = new MockERC20("Mock Token 2", "MOCK2", 12);
        vm.prank(ASSET_MANAGER);
        vault.addAssetWithDecimals(address(asset2), 12, false, true);

        assertEq(vault.getAsset(address(asset2)).active, false, "asset2 should not be active");
        assertEq(vault.getAsset(address(asset2)).decimals, 12, "asset2 should have 10 decimals");
        assertEq(vault.getAssetWithdrawable(address(asset2)), true, "asset2 should be withdrawable");
    }

    function test_Vault_addAsset_nullAddress() public {
        vm.prank(ASSET_MANAGER);
        vm.expectRevert();
        vault.addAsset(address(0), true);

        vm.prank(ASSET_MANAGER);
        vm.expectRevert();
        vault.addAssetWithDecimals(address(0), 18, true, true);

        vm.prank(ASSET_MANAGER);
        vm.expectRevert();
        vault.addAssetWithDecimals(address(0), 18, true);
    }

    function test_Vault_addAsset_duplicateAddress() public {
        vm.startPrank(ASSET_MANAGER);
        vault.addAssetWithDecimals(address(asset), 18, true, true);

        vm.expectRevert(abi.encodeWithSelector(IVault.DuplicateAsset.selector, address(asset)));
        vault.addAssetWithDecimals(address(asset), 18, true, true);

        vm.expectRevert(abi.encodeWithSelector(IVault.DuplicateAsset.selector, address(asset)));
        vault.addAssetWithDecimals(address(asset), 18, true);
    }

    function test_Vault_addAsset_unauthorized() public {
        vm.expectRevert();
        vault.addAsset(address(asset), true);

        vm.expectRevert();
        vault.addAssetWithDecimals(address(asset), 18, true, true);

        vm.expectRevert();
        vault.addAssetWithDecimals(address(asset), 18, true);
    }
}
