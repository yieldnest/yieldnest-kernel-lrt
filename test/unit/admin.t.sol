// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupKernelStrategy} from "test/unit/helpers/SetupKernelStrategy.sol";

contract KernelStrategyAdminUintTest is SetupKernelStrategy {
    function setUp() public {
        deploy();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_Vault_setStakerGateway() public {
        address sg = address(200);
        vm.prank(ADMIN);
        vault.setStakerGateway(sg);
        assertEq(vault.getStakerGateway(), sg);
    }

    function test_Vault_setStakerGateway_nullAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        vault.setStakerGateway(address(0));
    }

    function test_Vault_setStakerGateway_unauthorized() public {
        address sg = address(200);
        vm.expectRevert();
        vault.setStakerGateway(sg);
    }

    function test_Vault_setSyncDeposit() public {
        vm.prank(ADMIN);
        vault.setSyncDeposit(true);
        assertEq(vault.getSyncDeposit(), true);

        vm.prank(ADMIN);
        vault.setSyncDeposit(false);
        assertEq(vault.getSyncDeposit(), false);
    }

    function test_Vault_setSyncDeposit_unauthorized() public {
        vm.expectRevert();
        vault.setSyncDeposit(true);
    }

    function test_Vault_setSyncWithdraw() public {
        vm.prank(ADMIN);
        vault.setSyncWithdraw(true);
        assertEq(vault.getSyncWithdraw(), true);

        vm.prank(ADMIN);
        vault.setSyncWithdraw(false);
        assertEq(vault.getSyncWithdraw(), false);
    }

    function test_Vault_setSyncWithdraw_unauthorized() public {
        vm.expectRevert();
        vault.setSyncWithdraw(true);
    }
}
