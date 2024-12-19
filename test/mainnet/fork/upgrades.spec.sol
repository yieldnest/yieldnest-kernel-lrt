// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";



contract YnBTCkUpgradeTest is Test, MainnetActors {
    KernelStrategy public vault;
    address public constant WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC; // TODO: Add real whale address

    function setUp() public {
        vault = KernelStrategy(payable(MC.YNBTCK));
        vm.label(address(vault), "ynBTCk");
        vm.label(MC.BTCB, "BTCB");
    }

    function testDepositWithdrawBTCB() public {
        uint256 amount = 1e18; // 1 BTCB
        
        // Get BTCB from whale
        vm.startPrank(WHALE);
        IERC20(MC.BTCB).transfer(address(this), 1e18);
        vm.stopPrank();

        // Initial deposit of 1000 BTCB to have liquidity in vault
        {

            address randomDepositor = makeAddr("randomDepositor");
            uint256 initialDeposit = 100e18;
            vm.startPrank(WHALE);
            IERC20(MC.BTCB).transfer(randomDepositor, initialDeposit);
            vm.stopPrank();
            
            // Do deposit as random depositor
            vm.startPrank(randomDepositor);
            IERC20(MC.BTCB).approve(address(vault), initialDeposit);
            vault.depositAsset(MC.BTCB, initialDeposit, randomDepositor);
            vm.stopPrank();
        }

        // Approve vault to spend BTCB
        IERC20(MC.BTCB).approve(address(vault), amount);

        // Get initial balances
        uint256 initialBTCBBalance = IERC20(MC.BTCB).balanceOf(address(this));
        uint256 initialShares = vault.balanceOf(address(this));

        // Deposit BTCB
        uint256 shares = vault.depositAsset(MC.BTCB, amount, address(this));
        
        // Check deposit results
        assertEq(IERC20(MC.BTCB).balanceOf(address(this)), initialBTCBBalance - amount, "BTCB not transferred");
        assertEq(vault.balanceOf(address(this)), initialShares + shares, "Shares not minted");

        // Withdraw BTCB
        vault.redeemAsset(MC.BTCB, shares, address(this), address(this));

        // Print current balances
        console.log("Current BTCB balance:", IERC20(MC.BTCB).balanceOf(address(this)));
        console.log("Current vault shares:", vault.balanceOf(address(this)));

        // Check withdrawal results  
        assertGe(IERC20(MC.BTCB).balanceOf(address(this)), (initialBTCBBalance * 999) / 1000, "Less than 99.9% BTCB returned");
        assertLe(IERC20(MC.BTCB).balanceOf(address(this)), (initialBTCBBalance * 9991) / 10000, "More than 99.9% BTCB returned");
        assertEq(vault.balanceOf(address(this)), initialShares, "Shares not burned");

        // Print rate (totalAssets/totalSupply)
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        console.log("Rate (totalAssets/totalSupply):", totalAssets * 1e18 / totalSupply);
    }

    function testUpgradeVaultWithOwner() public {
        // Deploy new implementation
        KernelStrategy newImplementation = new KernelStrategy();

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(ProxyUtils.getProxyAdmin(address(vault)));
        
        // Upgrade directly as owner
        vm.prank(0x721688652DEa9Cabec70BD99411EAEAB9485d436);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(vault)), address(newImplementation), "");

        // Verify upgrade
        assertEq(ProxyUtils.getImplementation(address(vault)), address(newImplementation));
    }

    function testUpgradeVaultWithTimelock() public {

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(ProxyUtils.getProxyAdmin(address(vault)));

        // Transfer ownership to timelock
        vm.prank(proxyAdmin.owner());
        proxyAdmin.transferOwnership(0xE698E3c74917C2bF80E63366673179293E4AB856);

        // Verify ownership transfer
        assertEq(proxyAdmin.owner(), 0xE698E3c74917C2bF80E63366673179293E4AB856);



        // Deploy new implementation
        KernelStrategy newImplementation = new KernelStrategy();

        // Get proxy admin and timelock
        console.log("ProxyAdmin:", address(proxyAdmin));
        TimelockController timelock = TimelockController(payable(proxyAdmin.owner()));

        // Encode upgrade call
        bytes memory upgradeData = abi.encodeWithSelector(
            proxyAdmin.upgradeAndCall.selector, 
            address(vault),
            address(newImplementation),
            ""
        );

        // Schedule upgrade
        vm.startPrank(ADMIN);
        timelock.schedule(
            address(proxyAdmin),
            0,
            upgradeData,
            bytes32(0),
            bytes32(0),
            timelock.getMinDelay()
        );
        vm.stopPrank();

        // Wait for timelock delay
        vm.warp(block.timestamp + timelock.getMinDelay());

        // Execute upgrade
        vm.startPrank(ADMIN);
        timelock.execute(
            address(proxyAdmin),
            0,
            upgradeData,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();
        // Verify upgrade
        assertEq(ProxyUtils.getImplementation(address(vault)), address(newImplementation));
    }
}
