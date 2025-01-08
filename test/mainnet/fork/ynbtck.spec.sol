// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {BaseForkTest} from "./BaseForkTest.sol";

import {MainnetContracts} from "script/Contracts.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";

contract YnBTCkForkTest is BaseForkTest {
    KernelStrategy public strategy;

    function setUp() public {
        vault = IVault(payable(address(MainnetContracts.YNBTCK)));
        strategy = KernelStrategy(payable(address(vault)));
        stakerGateway = IStakerGateway(strategy.getStakerGateway());

        asset = IERC20(MainnetContracts.BTCB);
    }

    function upgradeVaultWithTimelock() internal {
        KernelStrategy newImplementation = new KernelStrategy();
        // TODO: uncomment this when we have a timelock and remove repeated code
        // _upgradeVaultWithTimelock(address(newImplementation));

        address vaultAddress = address(vault);

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(getProxyAdmin(vaultAddress));

        assertEq(proxyAdmin.owner(), ADMIN, "Proxy admin owner should be admin");

        vm.startPrank(ADMIN);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(payable(address(vault))), address(newImplementation), "");
        vm.stopPrank();

        // Verify upgrade was successful
        assertEq(
            getImplementation(vaultAddress),
            address(newImplementation),
            "Implementation address should match new implementation"
        );
    }

    function testUpgrade() public {
        uint256 totalAssetsBefore = strategy.totalAssets();
        uint256 totalSupplyBefore = strategy.totalSupply();
        uint256 previewWithdrawBefore = strategy.previewWithdraw(1000 ether);
        uint256 previewRedeemBefore = strategy.previewRedeem(1000 ether);
        uint256 previewDepositBefore = strategy.previewDeposit(1000 ether);
        uint256 previewMintBefore = strategy.previewMint(1000 ether);
        uint8 decimalsBefore = strategy.decimals();
        string memory nameBefore = strategy.name();
        string memory symbolBefore = strategy.symbol();
        bool syncDepositBefore = strategy.getSyncDeposit();
        bool syncWithdrawBefore = strategy.getSyncWithdraw();
        address strategyGatewayBefore = strategy.getStakerGateway();
        address providerBefore = strategy.provider();
        address[] memory assetsBefore = strategy.getAssets();

        upgradeVaultWithTimelock();

        // Verify total assets and supply remain unchanged
        assertEq(strategy.totalAssets(), totalAssetsBefore, "Total assets should remain unchanged");
        assertEq(strategy.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");
        assertEq(strategy.previewMint(1000 ether), previewMintBefore, "Preview mint should remain unchanged");
        assertEq(strategy.previewRedeem(1000 ether), previewRedeemBefore, "Preview redeem should remain unchanged");
        assertEq(strategy.previewWithdraw(1000 ether), previewWithdrawBefore, "Preview withdraw should remain unchanged");
        assertEq(strategy.previewDeposit(1000 ether), previewDepositBefore, "Preview deposit should remain unchanged");
        assertEq(strategy.decimals(), decimalsBefore, "Decimals should remain unchanged");
        assertEq(strategy.name(), nameBefore, "Name should remain unchanged");
        assertEq(strategy.symbol(), symbolBefore, "Symbol should remain unchanged");

        assertEq(strategy.getSyncDeposit(), syncDepositBefore, "SyncDeposit should remain unchanged");
        assertEq(strategy.getSyncWithdraw(), syncWithdrawBefore, "SyncWithdraw should remain unchanged");

        assertEq(strategy.getStakerGateway(), strategyGatewayBefore, "StrategyGateway should remain unchanged");

        assertEq(strategy.provider(), providerBefore, "Provider should remain unchanged");
        assertEq(strategy.getAssets(), assetsBefore, "Assets should remain unchanged");
    }

    function testDepositBeforeUpgrade() public {
        depositIntoVault(address(asset), 100 ether);
    }

    function testDepositAfterUpgrade() public {
        upgradeVaultWithTimelock();
        depositIntoVault(address(asset), 100 ether);
    }

    function testWithdrawBeforeUpgrade() public {
        depositIntoVault(address(asset), 100 ether);
        withdrawFromVault(address(asset), 50 ether);
    }

    function testWithdrawAfterUpgrade() public {
        depositIntoVault(address(asset), 100 ether);
        upgradeVaultWithTimelock();
        withdrawFromVault(address(asset), 50 ether);
    }

   
    function testAddRoleAndDeactivateAsset() public {
        // TODO: uncomment this when we have a timelock and remove repeated code
        // KernelStrategy newImplementation = new KernelStrategy();
        // _addRoleAndModifyAsset(address(strategy), address(newImplementation), false);
        // upgradeVaultWithTimelock();

        // Grant ASSET_MANAGER_ROLE to alice
        bytes32 ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");

        // Grant role directly since it doesn't use timelock
        vm.startPrank(ADMIN);
        strategy.grantRole(ASSET_MANAGER_ROLE, alice);
        vm.stopPrank();

        // Verify role was granted
        assertTrue(strategy.hasRole(ASSET_MANAGER_ROLE, alice), "Alice should have asset manager role");

        vm.startPrank(alice);
        strategy.updateAsset(1, IVault.AssetUpdateFields({active: false}));
        vm.stopPrank();

        // Get asset at index 1
        address assetAtIndex = vault.getAssets()[1];

        // Get asset params and verify active status
        IVault.AssetParams memory params = vault.getAsset(assetAtIndex);
        assertFalse(params.active, "Asset should be inactive");
        assertEq(assetAtIndex, MainnetContracts.SOLVBTC, "Asset at index 1 should be kernel vault");
    }
   
    function testAddRoleAndAddFee() public {
        // TODO: uncomment this when we have a timelock and remove repeated code    
        // KernelStrategy newImplementation = new KernelStrategy();
        // _addRoleAndAddFee(address(strategy), address(newImplementation));
        upgradeVaultWithTimelock();

        // Grant FEE_MANAGER_ROLE to alice
        bytes32 FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

        // Grant roles directly since it doesn't use timelock
        vm.startPrank(ADMIN);
        strategy.grantRole(FEE_MANAGER_ROLE, alice);
        vm.stopPrank();

        assertTrue(strategy.hasRole(FEE_MANAGER_ROLE, alice), "Alice should have fee manager role");

        // Set base withdrawal fee to 50 basis points (0.5%)
        uint64 newFee = 50_000; // 50_000 = 0.5% (1e8 = 100%)
        vm.startPrank(alice);
        strategy.setBaseWithdrawalFee(newFee);
        vm.stopPrank();

        // Verify fee was set correctly
        assertEq(strategy.baseWithdrawalFee(), newFee, "Base withdrawal fee should be set to 0.5%");
    }
}
