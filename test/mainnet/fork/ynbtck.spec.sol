// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MainnetContracts} from "script/Contracts.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";
import {BTCRateProvider} from "src/module/BTCRateProvider.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {console} from "lib/forge-std/src/console.sol";


import {KernelStrategy} from "src/KernelStrategy.sol";

contract YnBTCkForkTest is BaseForkTest {
    function setUp() public {
        vault = KernelStrategy(payable(address(MainnetContracts.YNBTCK)));
        stakerGateway = IStakerGateway(vault.getStakerGateway());

        asset = IERC20(MainnetContracts.BTCB);
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
    }

    function testUpgrade() public {
        _testVaultUpgrade();
    }

    function testDepositBeforeUpgrade() public {
        _depositIntoVault(alice, 100 ether);
    }

    function testDepositAfterUpgrade() public {
        _upgradeVault();
        _depositIntoVault(alice, 100 ether);
    }

    function testWithdrawBeforeUpgrade() public {
        _depositIntoVault(alice, 100 ether);
        _withdrawFromVault(alice, 50 ether);
    }

    function testWithdrawAfterUpgrade() public {
        _depositIntoVault(alice, 100 ether);
        _upgradeVault();
        _withdrawFromVault(alice, 50 ether);
    }

    function testAddRoleAndDeactivateAsset() public {
        _upgradeVault();
        _addRoleAndModifyAsset(MainnetContracts.SOLVBTC, false);
    }

    function testAddRoleAndAddFee() public {
        _upgradeVault();
        _addRoleAndAddFee();
    }
}
