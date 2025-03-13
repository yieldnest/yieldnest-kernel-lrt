// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MainnetContracts} from "script/Contracts.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

contract YnWBNBkForkTest is BaseForkTest {
    address public ynbnbx = address(MainnetContracts.YNBNBX);

    function setUp() public {
        vault = KernelStrategy(payable(address(MainnetContracts.YNWBNBK)));
        stakerGateway = IStakerGateway(KernelStrategy(payable(address(vault))).getStakerGateway());

        asset = IERC20(MainnetContracts.WBNB);
    }

    function _upgradeVault() internal override {
        super._upgradeVault();
        // Set WBNB as withdrawable after upgrade
        vm.startPrank(ADMIN);
        // Grant ASSET_MANAGER_ROLE to ADMIN
        KernelStrategy(payable(address(vault))).grantRole(
            KernelStrategy(payable(address(vault))).ASSET_MANAGER_ROLE(), ADMIN
        );
        KernelStrategy(payable(address(vault))).setAssetWithdrawable(MainnetContracts.WBNB, true);
        vm.stopPrank();
    }

    function upgradeVaultWithTimelock() internal {
        KernelStrategy newImplementation = new KernelStrategy();
        _upgradeVaultWithTimelock(address(newImplementation));
    }

    function testUpgrade() public {
        _testVaultUpgrade();
        assertTrue(vault.hasRole(vault.ALLOCATOR_ROLE(), address(ynbnbx)), "Allocator should have role");
    }

    function testDepositBeforeUpgrade() public {
        _depositIntoVault(address(ynbnbx), 100 ether);
    }

    function testDepositAfterUpgrade() public {
        _upgradeVault();
        _depositIntoVault(address(ynbnbx), 100 ether);
    }

    function testWithdrawBeforeUpgrade() public {
        _depositIntoVault(address(ynbnbx), 100 ether);
        _withdrawFromVault(address(ynbnbx), 50 ether);
    }

    function testWithdrawAfterUpgrade() public {
        _depositIntoVault(address(ynbnbx), 100 ether);
        _upgradeVault();
        _withdrawFromVault(address(ynbnbx), 50 ether);
    }

    function testAddRoleAndActivateAsset() public {
        _upgradeVault();
        address kernelVault = stakerGateway.getVault(address(asset));
        _addRoleAndModifyAsset(address(kernelVault), true);
    }

    function testAddRoleAndAddFee() public {
        _upgradeVault();
        _addRoleAndAddFee();
    }
}
