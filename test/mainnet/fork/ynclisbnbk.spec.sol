// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MainnetContracts} from "script/Contracts.sol";
import {MainnetKernelActors} from "script/KernelActors.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";
import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";

import {KernelClisStrategy} from "src/KernelClisStrategy.sol";

contract YnClisBNBkForkTest is Test, MainnetKernelActors, ProxyUtils {
    KernelClisStrategy public vault;
    IERC20 public wbnb;
    IERC20 public clisbnb;
    IStakerGateway public stakerGateway;
    address public ynbnbx = address(MainnetContracts.YNBNBX);

    function setUp() public {
        vault = KernelClisStrategy(payable(address(MainnetContracts.YNCLISBNBK)));
        stakerGateway = IStakerGateway(vault.getStakerGateway());

        wbnb = IERC20(MainnetContracts.WBNB);
        clisbnb = IERC20(MainnetContracts.CLISBNB);
    }

    function depositIntoVault() internal {
        uint256 depositAmount = 1000 ether;

        // Initial balances
        uint256 ynbnbxWBNBBefore = wbnb.balanceOf(ynbnbx);
        uint256 ynbnbxSharesBefore = vault.balanceOf(ynbnbx);

        // Store initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();
        // Store initial vault WBNB balance
        uint256 vaultWBNBBefore = stakerGateway.balanceOf(address(clisbnb), address(vault));

        // Give ynbnbx some WBNB
        deal(address(wbnb), ynbnbx, ynbnbxWBNBBefore + depositAmount);

        assertEq(wbnb.balanceOf(ynbnbx), ynbnbxWBNBBefore + depositAmount, "WBNB balance incorrect after deal");

        vm.startPrank(ynbnbx);
        // Approve vault to spend WBNB
        wbnb.approve(address(vault), depositAmount);
        // Deposit WBNB to get shares
        uint256 shares = vault.deposit(depositAmount, ynbnbx);

        vm.stopPrank();

        // Check balances after deposit
        assertEq(wbnb.balanceOf(ynbnbx), ynbnbxWBNBBefore, "WBNB balance incorrect");
        assertEq(vault.balanceOf(ynbnbx), ynbnbxSharesBefore + shares, "Should have received shares");

        // Check vault state after deposit
        assertEq(
            vault.totalAssets(), initialTotalAssets + depositAmount, "Total assets should increase by deposit amount"
        );
        assertEq(vault.totalSupply(), initialTotalSupply + shares, "Total supply should increase by shares");

        // Check that vault WBNB balance increased by deposit amount
        assertEq(
            stakerGateway.balanceOf(address(clisbnb), address(vault)),
            vaultWBNBBefore + depositAmount,
            "Vault balance should increase by deposit"
        );
    }

    function withdrawFromVault() internal {
        uint256 withdrawAmount = 100 ether;

        // Initial balances
        uint256 ynbnbxWBNBBefore = wbnb.balanceOf(ynbnbx);
        uint256 ynbnbxSharesBefore = vault.balanceOf(ynbnbx);

        // Store initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();
        // Store initial vault WBNB balance
        uint256 vaultWBNBBefore = stakerGateway.balanceOf(address(clisbnb), address(vault));

        vm.startPrank(ynbnbx);

        // Deposit WBNB to get shares
        uint256 shares = vault.withdrawAsset(address(wbnb), withdrawAmount, ynbnbx, ynbnbx);

        vm.stopPrank();

        // Check balances after deposit
        assertEq(wbnb.balanceOf(ynbnbx), ynbnbxWBNBBefore + withdrawAmount, "WBNB balance incorrect");
        assertEq(vault.balanceOf(ynbnbx), ynbnbxSharesBefore - shares, "Should have burnt shares");

        // Check vault state after deposit
        assertEq(
            vault.totalAssets(), initialTotalAssets - withdrawAmount, "Total assets should decrease by withdraw amount"
        );
        assertEq(vault.totalSupply(), initialTotalSupply - shares, "Total supply should decrease by shares");

        // Check that vault WBNB balance increased by deposit amount
        assertEq(
            stakerGateway.balanceOf(address(clisbnb), address(vault)),
            vaultWBNBBefore - withdrawAmount,
            "Vault balance should decrease by withdraw amount"
        );
    }

    function upgradeVaultWithTimelock() internal {
        KernelClisStrategy newImplementation = new KernelClisStrategy();
        address vaultAddress = address(vault);

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(getProxyAdmin(vaultAddress));

        TimelockController timelock = TimelockController(payable(proxyAdmin.owner()));

        // Encode upgrade call
        bytes memory upgradeData =
            abi.encodeWithSelector(proxyAdmin.upgradeAndCall.selector, vaultAddress, address(newImplementation), "");

        uint256 delay = 86400;

        // Schedule upgrade
        vm.startPrank(ADMIN);
        timelock.schedule(address(proxyAdmin), 0, upgradeData, bytes32(0), bytes32(0), delay);
        vm.stopPrank();
        uint256 timestamp = block.timestamp;
        // Wait for timelock delay
        vm.warp(timestamp + delay);

        // Execute upgrade
        vm.startPrank(ADMIN);
        timelock.execute(address(proxyAdmin), 0, upgradeData, bytes32(0), bytes32(0));
        vm.stopPrank();
        // warp back to original timestamp for oracle 
        vm.warp(timestamp);

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

        assertTrue(vault.hasRole(vault.ALLOCATOR_ROLE(), address(ynbnbx)), "Allocator should have role");
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

    function testAddRoleAndActivateAsset() public {
        upgradeVaultWithTimelock();

        // Grant ASSET_MANAGER_ROLE to alice
        bytes32 ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
        address alice = makeAddr("alice");

        // Grant role directly since it doesn't use timelock
        vm.startPrank(ADMIN);
        vault.grantRole(ASSET_MANAGER_ROLE, alice);
        vm.stopPrank();

        // Verify role was granted
        assertTrue(vault.hasRole(ASSET_MANAGER_ROLE, alice), "Alice should have asset manager role");

        vm.startPrank(alice);
        vault.updateAsset(1, IVault.AssetUpdateFields({active: true}));
        vm.stopPrank();

        // Get asset at index 1
        address assetAtIndex = vault.getAssets()[1];

        address kernelVault = stakerGateway.getVault(address(clisbnb));

        // Get asset params and verify active status
        IVault.AssetParams memory params = vault.getAsset(assetAtIndex);
        assertTrue(params.active, "Asset should be active");
        assertEq(assetAtIndex, kernelVault, "Asset at index 1 should be kernel vault");
    }

    function testAddRoleAndAddFee() public {
        upgradeVaultWithTimelock();

        // Grant FEE_MANAGER_ROLE to alice
        address alice = makeAddr("alice");
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
