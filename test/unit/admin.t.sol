// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {SetupKernelStrategy} from "test/unit/helpers/SetupKernelStrategy.sol";

contract KernelStrategyAdminUintTest is SetupKernelStrategy {
    function setUp() public {
        deploy();

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
}
