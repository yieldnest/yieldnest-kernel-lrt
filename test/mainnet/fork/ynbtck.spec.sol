// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MainnetContracts} from "script/Contracts.sol";
import {MainnetKernelActors} from "script/KernelActors.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";
import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";

contract YnBTCkForkTest is Test, MainnetKernelActors, ProxyUtils {
    KernelStrategy public vault;
    IERC20 public btcb;
    IStakerGateway public stakerGateway;
    address public alice;

    function setUp() public {
        vault = KernelStrategy(payable(address(MainnetContracts.YNBTCK)));
        stakerGateway = IStakerGateway(vault.getStakerGateway());

        btcb = IERC20(MainnetContracts.BTCB);
        alice = makeAddr("alice");
    }

    function depositIntoVault() internal {
        uint256 depositAmount = 100 ether;

        // Initial balances
        uint256 aliceBTCBBefore = btcb.balanceOf(alice);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        // Store initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();
        // Store initial vault BTCB balance
        uint256 vaultBTCBBefore = stakerGateway.balanceOf(address(btcb), address(vault));

        // Give alice some BTCB
        deal(address(btcb), alice, aliceBTCBBefore + depositAmount);

        assertEq(btcb.balanceOf(alice), aliceBTCBBefore + depositAmount, "BTCB balance incorrect after deal");

        vm.startPrank(alice);
        // Approve vault to spend BTCB
        btcb.approve(address(vault), depositAmount);
        // Deposit BTCB to get shares
        uint256 shares = vault.deposit(depositAmount, alice);

        vm.stopPrank();

        // Check balances after deposit
        assertEq(btcb.balanceOf(alice), aliceBTCBBefore, "BTCB balance incorrect");
        assertEq(vault.balanceOf(alice), aliceSharesBefore + shares, "Should have received shares");

        // Check vault state after deposit
        assertEq(
            vault.totalAssets(), initialTotalAssets + depositAmount, "Total assets should increase by deposit amount"
        );
        assertEq(vault.totalSupply(), initialTotalSupply + shares, "Total supply should increase by shares");

        // Check that vault BTCB balance increased by deposit amount
        assertEq(
            stakerGateway.balanceOf(address(btcb), address(vault)),
            vaultBTCBBefore + depositAmount,
            "Vault balance should increase by deposit"
        );
    }

    function withdrawFromVault() internal {
        uint256 withdrawAmount = 50 ether;

        // Initial balances
        uint256 aliceBTCBBefore = btcb.balanceOf(alice);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        // Store initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();
        // Store initial vault BTCB balance
        uint256 vaultBTCBBefore = stakerGateway.balanceOf(address(btcb), address(vault));

        vm.startPrank(alice);

        // Deposit BTCB to get shares
        uint256 shares = vault.withdrawAsset(address(btcb), withdrawAmount, alice, alice);

        vm.stopPrank();

        // Check balances after deposit
        assertEq(btcb.balanceOf(alice), aliceBTCBBefore + withdrawAmount, "BTCB balance incorrect");
        assertEq(vault.balanceOf(alice), aliceSharesBefore - shares, "Should have burnt shares");

        // Check vault state after deposit
        assertEq(
            vault.totalAssets(), initialTotalAssets - withdrawAmount, "Total assets should decrease by withdraw amount"
        );
        assertEq(vault.totalSupply(), initialTotalSupply - shares, "Total supply should decrease by shares");

        // Check that vault BTCB balance increased by deposit amount
        assertEq(
            stakerGateway.balanceOf(address(btcb), address(vault)),
            vaultBTCBBefore - withdrawAmount,
            "Vault balance should decrease by withdraw amount"
        );
    }

    function upgradeVaultWithTimelock() internal {
        KernelStrategy newImplementation = new KernelStrategy();
        address vaultAddress = address(vault);

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(getProxyAdmin(vaultAddress));

        assertEq(proxyAdmin.owner(), ADMIN, "Proxy admin owner should be admin");

        vm.startPrank(ADMIN);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(payable(address(vault))), address(newImplementation), "");
        vm.stopPrank();

        // TODO: uncomment this when we have a timelock
        /*
        TimelockController timelock = TimelockController(payable(proxyAdmin.owner()));

        // Encode upgrade call
        bytes memory upgradeData =
        abi.encodeWithSelector(proxyAdmin.upgradeAndCall.selector, vaultAddress, address(newImplementation), "");

        uint256 delay = 86400;

        // Schedule upgrade
        vm.startPrank(ADMIN);
        timelock.schedule(address(proxyAdmin), 0, upgradeData, bytes32(0), bytes32(0), delay);
        vm.stopPrank();

        // Wait for timelock delay
        vm.warp(block.timestamp + delay);

        // Execute upgrade
        vm.startPrank(ADMIN);
        timelock.execute(address(proxyAdmin), 0, upgradeData, bytes32(0), bytes32(0));
        vm.stopPrank();

        */

        // Verify upgrade was successful
        assertEq(
            getImplementation(vaultAddress),
            address(newImplementation),
            "Implementation address should match new implementation"
        );
    }

    function testUpgrade() public {
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 previewWithdrawBefore = vault.previewWithdraw(1000 ether);
        uint256 previewRedeemBefore = vault.previewRedeem(1000 ether);
        uint256 previewDepositBefore = vault.previewDeposit(1000 ether);
        uint256 previewMintBefore = vault.previewMint(1000 ether);
        uint8 decimalsBefore = vault.decimals();
        string memory nameBefore = vault.name();
        string memory symbolBefore = vault.symbol();
        bool syncDepositBefore = vault.getSyncDeposit();
        bool syncWithdrawBefore = vault.getSyncWithdraw();
        address strategyGatewayBefore = vault.getStakerGateway();
        address providerBefore = vault.provider();
        address[] memory assetsBefore = vault.getAssets();

        upgradeVaultWithTimelock();

        // Verify total assets and supply remain unchanged
        assertEq(vault.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged");
        assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");
        assertEq(vault.previewMint(1000 ether), previewMintBefore, "Preview mint should remain unchanged");
        assertEq(vault.previewRedeem(1000 ether), previewRedeemBefore, "Preview redeem should remain unchanged");
        assertEq(vault.previewWithdraw(1000 ether), previewWithdrawBefore, "Preview withdraw should remain unchanged");
        assertEq(vault.previewDeposit(1000 ether), previewDepositBefore, "Preview deposit should remain unchanged");
        assertEq(vault.decimals(), decimalsBefore, "Decimals should remain unchanged");
        assertEq(vault.name(), nameBefore, "Name should remain unchanged");
        assertEq(vault.symbol(), symbolBefore, "Symbol should remain unchanged");

        assertEq(vault.getSyncDeposit(), syncDepositBefore, "SyncDeposit should remain unchanged");
        assertEq(vault.getSyncWithdraw(), syncWithdrawBefore, "SyncWithdraw should remain unchanged");

        assertEq(vault.getStakerGateway(), strategyGatewayBefore, "StrategyGateway should remain unchanged");

        assertEq(vault.provider(), providerBefore, "Provider should remain unchanged");
        assertEq(vault.getAssets(), assetsBefore, "Assets should remain unchanged");
    }

    function testDepositBeforeUpgrade() public {
        depositIntoVault();
    }

    function testDepositAfterUpgrade() public {
        upgradeVaultWithTimelock();
        depositIntoVault();
    }

    function testWithdrawBeforeUpgrade() public {
        depositIntoVault();
        withdrawFromVault();
    }

    function testWithdrawAfterUpgrade() public {
        depositIntoVault();
        upgradeVaultWithTimelock();
        withdrawFromVault();
    }

    function testAddRoleAndDeactivateAsset() public {
        upgradeVaultWithTimelock();

        // Grant ASSET_MANAGER_ROLE to alice
        bytes32 ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");

        // Grant role directly since it doesn't use timelock
        vm.startPrank(ADMIN);
        vault.grantRole(ASSET_MANAGER_ROLE, alice);
        vm.stopPrank();

        // Verify role was granted
        assertTrue(vault.hasRole(ASSET_MANAGER_ROLE, alice), "Alice should have asset manager role");

        vm.startPrank(alice);
        vault.updateAsset(1, IVault.AssetUpdateFields({active: false}));
        vm.stopPrank();

        // Get asset at index 1
        address assetAtIndex = vault.getAssets()[1];

        // Get asset params and verify active status
        IVault.AssetParams memory params = vault.getAsset(assetAtIndex);
        assertFalse(params.active, "Asset should be inactive");
        assertEq(assetAtIndex, MainnetContracts.SOLVBTC, "Asset at index 1 should be kernel vault");
    }

    function testAddRoleAndAddFee() public {
        upgradeVaultWithTimelock();

        // Grant FEE_MANAGER_ROLE to alice
        bytes32 FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

        // Grant roles directly since it doesn't use timelock
        vm.startPrank(ADMIN);
        vault.grantRole(FEE_MANAGER_ROLE, alice);
        vm.stopPrank();

        assertTrue(vault.hasRole(FEE_MANAGER_ROLE, alice), "Alice should have fee manager role");

        // Set base withdrawal fee to 50 basis points (0.5%)
        uint64 newFee = 50_000; // 50_000 = 0.5% (1e8 = 100%)
        vm.startPrank(alice);
        vault.setBaseWithdrawalFee(newFee);
        vm.stopPrank();

        // Verify fee was set correctly
        assertEq(vault.baseWithdrawalFee(), newFee, "Base withdrawal fee should be set to 0.5%");
    }
}
