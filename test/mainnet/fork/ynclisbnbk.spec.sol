// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MainnetContracts} from "script/Contracts.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {KernelClisStrategy} from "src/KernelClisStrategy.sol";

contract YnClisBNBkForkTest is BaseForkTest {
    IERC20 public clisbnb;
    address public ynbnbx = address(MainnetContracts.YNBNBX);

    function setUp() public {
        // setting up vault and strategy for inherited utility functions and tests
        vault = KernelClisStrategy(payable(address(MainnetContracts.YNCLISBNBK)));

        stakerGateway = IStakerGateway(vault.getStakerGateway());

        asset = IERC20(MainnetContracts.WBNB);
        clisbnb = IERC20(MainnetContracts.CLISBNB);
    }

    function _getStakedBalance() internal view override returns (uint256) {
        return stakerGateway.balanceOf(address(clisbnb), address(vault));
    }

    function _upgradeVault() internal override {
        KernelClisStrategy newImplementation = new KernelClisStrategy();
        _upgradeVaultWithTimelock(address(newImplementation));

        // Set WBNB as withdrawable after upgrade
        vm.startPrank(ADMIN);
        // Grant ASSET_MANAGER_ROLE to ADMIN
        KernelStrategy(payable(address(vault))).grantRole(
            KernelStrategy(payable(address(vault))).ASSET_MANAGER_ROLE(),
            ADMIN
        );
        KernelClisStrategy(payable(address(vault))).setAssetWithdrawable(MainnetContracts.WBNB, true);
        vm.stopPrank();
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

    function testAddRoleAndDeactivateAsset() public {
        _upgradeVault();
        address kernelVault = stakerGateway.getVault(address(clisbnb));
        _addRoleAndModifyAsset(address(kernelVault), true);
    }

    function testAddRoleAndAddFee() public {
        _upgradeVault();
        _addRoleAndAddFee();
    }
}
