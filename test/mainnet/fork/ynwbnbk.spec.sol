// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {BaseForkTest} from "./BaseForkTest.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";

contract YnWBNBkForkTest is BaseForkTest {
    KernelStrategy public strategy;
    address public ynbnbx = address(MainnetContracts.YNBNBX);

    function setUp() public {
        vault = KernelStrategy(payable(address(MainnetContracts.YNWBNBK)));
        strategy = KernelStrategy(payable(address(vault)));
        stakerGateway = IStakerGateway(KernelStrategy(payable(address(vault))).getStakerGateway());

        asset = IERC20(MainnetContracts.WBNB);
    }

    function upgradeVaultWithTimelock() internal {
        KernelStrategy newImplementation = new KernelStrategy();
        _upgradeVaultWithTimelock(address(newImplementation));
    }

    function testUpgrade() public {

        bool syncDepositBefore = strategy.getSyncDeposit();
        bool syncWithdrawBefore = strategy.getSyncWithdraw();
        address strategyGatewayBefore = strategy.getStakerGateway();

        KernelStrategy newImplementation = new KernelStrategy();

        _testVaultUpgrade(address(newImplementation));


        assertEq(strategy.getSyncDeposit(), syncDepositBefore, "SyncDeposit should remain unchanged");
        assertEq(strategy.getSyncWithdraw(), syncWithdrawBefore, "SyncWithdraw should remain unchanged");

        assertEq(strategy.getStakerGateway(), strategyGatewayBefore, "StrategyGateway should remain unchanged");

        assertTrue(strategy.hasRole(strategy.ALLOCATOR_ROLE(), address(ynbnbx)), "Allocator should have role");
    }

    function testDepositBeforeUpgrade() public {
        depositIntoVault(address(ynbnbx), 1000 ether);
    }

    function testDepositAfterUpgrade() public {
        upgradeVaultWithTimelock();
        depositIntoVault(address(ynbnbx), 1000 ether);
    }

    function testWithdrawBeforeUpgrade() public {
        depositIntoVault(address(ynbnbx), 1000 ether);
        withdrawFromVault(address(ynbnbx), 100 ether);
    }

    function testWithdrawAfterUpgrade() public {
        depositIntoVault(address(ynbnbx), 1000 ether);
        upgradeVaultWithTimelock();
        withdrawFromVault(address(ynbnbx), 100 ether);
    }

    function testAddRoleAndActivateAsset() public {
        KernelStrategy newImplementation = new KernelStrategy();
        _addRoleAndModifyAsset(address(strategy), address(newImplementation), address(asset), true);

    }

    function testAddRoleAndAddFee() public {
        KernelStrategy newImplementation = new KernelStrategy();
        _addRoleAndAddFee(address(strategy), address(newImplementation));

    }
}
