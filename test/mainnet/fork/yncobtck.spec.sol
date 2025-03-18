// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseForkTest} from "./BaseForkTest.sol";

import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {TokenUtils} from "test/mainnet/helpers/TokenUtils.sol";

contract YnCoBTCkForkTest is BaseForkTest {
    TokenUtils public tokenUtils;

    address public depositor = alice;

    function setUp() public {
        vault = KernelStrategy(payable(address(MainnetContracts.YNCOBTCK)));
        stakerGateway = IStakerGateway(vault.getStakerGateway());

        asset = IERC20(MainnetContracts.COBTC);
        tokenUtils = new TokenUtils(address(vault), stakerGateway);
    }

    function _upgradeVault() internal override {
        KernelStrategy newImplementation = new KernelStrategy();

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(getProxyAdmin(address(vault)));
        assertEq(proxyAdmin.owner(), 0xBEA8b88391Da9b3e8BbD007fE6cE2b9C8794320E, "Proxy admin owner should be timelock");

        // TODO: uncomment this when we have a timelock and remove repeated code
        _upgradeVaultWithTimelock(address(newImplementation));

        // Verify upgrade was successful
        assertEq(
            getImplementation(address(vault)),
            address(newImplementation),
            "Implementation address should match new implementation"
        );

        vm.stopPrank();

        // Deal asset to depositor
        deal(address(asset), depositor, 10000e8);
    }

    function testUpgrade() public {
        _testVaultUpgrade();
    }

    function testDepositBeforeUpgrade() public {
        _depositIntoVault(address(depositor), 100e8);
    }

    function testDepositAfterUpgrade() public {
        _upgradeVault();
        _depositIntoVault(address(depositor), 100e8);
    }

    function testWithdrawBeforeUpgrade() public {
        _depositIntoVault(address(depositor), 100e8);
        _withdrawFromVault(address(depositor), 50e8);
    }

    function testWithdrawAfterUpgrade() public {
        _depositIntoVault(address(depositor), 100e8);
        _upgradeVault();
        _withdrawFromVault(address(depositor), 50e8);
    }

    function testAddRoleAndAddFee() public {
        _upgradeVault();
        _addRoleAndAddFee();
    }
}
