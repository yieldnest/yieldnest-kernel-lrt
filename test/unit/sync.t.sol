// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {SetupKernelStrategy} from "test/unit/helpers/SetupKernelStrategy.sol";

contract KernelStrategySyncUnitTest is SetupKernelStrategy {
    uint256 internal constant DEPOSIT_AMOUNT = 10 ether;

    function setUp() public {
        deploy();

        deal(alice, INITIAL_BALANCE);
        wbnb.deposit{value: INITIAL_BALANCE}();
        wbnb.transfer(alice, INITIAL_BALANCE);

        vm.prank(alice);
        wbnb.approve(address(vault), type(uint256).max);
    }

    function test_Sync_deposit_whenSyncEnabled() public {
        assertTrue(vault.getSyncDeposit());

        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);
        assertGt(shares, 0, "No shares minted during sync deposit");
    }

    function test_Sync_deposit_whenSyncDisabled() public {
        vm.prank(ADMIN);
        vault.setSyncDeposit(false);
        assertFalse(vault.getSyncDeposit());

        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);
        assertGt(shares, 0, "No shares minted when sync disabled");
    }

    function test_Sync_withdraw_whenSyncEnabled() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);
        assertTrue(vault.getSyncWithdraw());

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        assertEq(vault.balanceOf(alice), 0, "Shares not burned after redeem");
    }

    function test_Sync_withdraw_whenSyncDisabled() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(ADMIN);
        vault.setSyncWithdraw(false);
        assertFalse(vault.getSyncWithdraw());

        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(shares, alice, alice);
    }

    function test_Sync_gatewayConsistency() public {
        address gw = vault.getStakerGateway();
        assertTrue(gw != address(0), "Gateway not set");

        bytes memory expected = _fetchGatewayState(gw);
        assertTrue(expected.length > 0, "Empty gateway state");
    }

    function test_Sync_allocatorDeposit_fuzz(uint256 amount) public {
        vm.assume(amount > 1e15 && amount < 50_000 ether);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        assertGt(shares, 0);
        assertEq(vault.totalAssets(), amount, "Total assets mismatch");
    }

    function _fetchGatewayState(address gateway) internal returns (bytes memory) {
        string[] memory cmd = new string[](3);
        cmd[0] = "bash";
        cmd[1] = "script/helpers/check-gateway.sh";
        cmd[2] = vm.toString(gateway);
        return vm.ffi(cmd);
    }
}
