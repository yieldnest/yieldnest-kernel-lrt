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

    function testAddEnzoBTC() public {
        // _upgradeVault();
        _addEnzoBTC();
    }

    function _addEnzoBTC() internal {

        address TIMELOCK = 0xE698E3c74917C2bF80E63366673179293E4AB856;
        vm.startPrank(TIMELOCK);

        // Deploy and set provider
        address provider = address(new BTCRateProvider());

        vault.setProvider(provider);

        // Add asset
        vault.addAsset(MainnetContracts.ENZOBTC, true);
        vault.addAssetWithDecimals(IStakerGateway(MainnetContracts.STAKER_GATEWAY).getVault(MainnetContracts.ENZOBTC), 8, false);

        vm.stopPrank();
        // Verify asset was added
        assertTrue( vault.getAsset(MainnetContracts.ENZOBTC).active, "enzoBTC should be active");
        assertEq( vault.getAsset(MainnetContracts.ENZOBTC).decimals, 8, "enzoBTC should have 8 decimals");


        // Impersonate enzoBTC whale
        address ENZO_WHALE = 0x16b9CA0A8f5b90a531286E2886BAc5e1A19072E3;
        vm.startPrank(ENZO_WHALE);

        uint256 amount = 10 * 1e8; // 100 enzoBTC (8 decimals)
        uint256 expectedTVLIncrease = 10 ether; // Expected 18 decimal increase

        uint256 beforeTVL = vault.totalAssets();

        IERC20(MainnetContracts.ENZOBTC).approve(address(vault), amount);
        vault.depositAsset(MainnetContracts.ENZOBTC, amount, ENZO_WHALE);

        assertEq(
            IERC20(MainnetContracts.ENZOBTC).balanceOf(address(vault)),
            0,
            "Vault should have received enzoBTC"
        );

        uint256 afterTVL = vault.totalAssets();
        assertEq(afterTVL - beforeTVL, expectedTVLIncrease, "TVL should increase by 100 ether");

        vm.stopPrank();
    }
}
