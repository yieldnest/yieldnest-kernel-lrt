// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";

import {IERC20, ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";

import {ISlisBnbStakeManager} from "lib/yieldnest-vault/src/interface/external/lista/ISlisBnbStakeManager.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetKernelActors} from "script/KernelActors.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {MigratedKernelStrategy} from "src/MigratedKernelStrategy.sol";
import {BaseVaultViewer, KernelVaultViewer} from "src/utils/KernelVaultViewer.sol";

import {VaultUtils} from "lib/yieldnest-vault/script/VaultUtils.sol";

import {VaultKernelUtils} from "script/VaultKernelUtils.sol";
import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {BNBRateProvider} from "src/module/BNBRateProvider.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";

contract YnBNBkTest is Test, AssertUtils, MainnetKernelActors, EtchUtils, VaultUtils, VaultKernelUtils, ProxyUtils {
    KernelStrategy public vault;
    BNBRateProvider public kernelProvider;
    IStakerGateway public stakerGateway;
    KernelVaultViewer public viewer;

    address public bob = address(0xB0B);

    function setUp() public {
        kernelProvider = new BNBRateProvider();
        etchProvider(address(kernelProvider));

        vault = deployMigrateVault();
        viewer = KernelVaultViewer(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new KernelVaultViewer()),
                        ADMIN,
                        abi.encodeWithSelector(BaseVaultViewer.initialize.selector, address(vault))
                    )
                )
            )
        );

        stakerGateway = IStakerGateway(MC.STAKER_GATEWAY);
        vm.label(MC.STAKER_GATEWAY, "kernel staker gateway");
        vm.label(address(vault), "kernel strategy");
        vm.label(address(kernelProvider), "kernel rate provider");

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SLISBNB);
        address config = IKernelVault(kernelVault).getConfig();
        bytes32 role = IKernelConfig(config).ROLE_MANAGER();

        vm.prank(MC.KERNEL_CONFIG_ADMIN);
        IKernelConfig(config).grantRole(role, address(this));

        IKernelVault(kernelVault).setDepositLimit(type(uint256).max);
    }

    function deployMigrateVault() internal returns (KernelStrategy) {
        MigratedKernelStrategy migrationVault = MigratedKernelStrategy(payable(MC.YNBNBK));

        uint256 previousTotalAssets = migrationVault.totalAssets();

        uint256 previousTotalSupply = migrationVault.totalSupply();

        address specificHolder = 0xCfac0990700eD9B67FeFBD4b26a79E426468a419;

        uint256 previousBalance = migrationVault.balanceOf(specificHolder);

        MigratedKernelStrategy implemention = new MigratedKernelStrategy();

        ProxyAdmin proxyAdmin = ProxyAdmin(getProxyAdmin(MC.YNBNBK));

        uint256 previousPreviewRedeem = migrationVault.previewRedeem(1e18);
        uint256 previousPreviewWithdraw = migrationVault.previewWithdraw(1e18);
        uint256 previousPreviewDeposit = migrationVault.previewDeposit(1e18);

        {
            vm.prank(proxyAdmin.owner());

            vm.expectRevert(Initializable.InvalidInitialization.selector);
            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(MC.YNBNBK),
                address(implemention),
                abi.encodeWithSelector(
                    Vault.initialize.selector,
                    address(ADMIN),
                    "YieldNest Restaked BNB - Kernel",
                    "ynBNBk",
                    18,
                    0,
                    true,
                    false
                )
            );
        }

        {
            MigratedKernelStrategy.Asset[] memory assets = new MigratedKernelStrategy.Asset[](3);

            assets[0] = MigratedKernelStrategy.Asset({asset: MC.WBNB, active: false});
            assets[1] = MigratedKernelStrategy.Asset({asset: MC.SLISBNB, active: true});
            assets[2] = MigratedKernelStrategy.Asset({asset: MC.BNBX, active: true});

            vm.prank(proxyAdmin.owner());

            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(MC.YNBNBK),
                address(implemention),
                abi.encodeWithSelector(
                    MigratedKernelStrategy.initializeAndMigrate.selector,
                    address(ADMIN),
                    "YieldNest Restaked BNB - Kernel",
                    "ynBNBk",
                    assets,
                    MC.STAKER_GATEWAY,
                    0 // base fee
                )
            );

            vault = KernelStrategy(payable(address(migrationVault)));
            configureVault(vault);
        }

        {
            assertEqThreshold(
                migrationVault.totalAssets(),
                previousTotalAssets,
                1000,
                "Total assets should remain the same after upgrade"
            );
            assertEqThreshold(
                migrationVault.totalSupply(),
                previousTotalSupply,
                1000,
                "Total supply should remain the same after upgrade"
            );
            assertEqThreshold(
                migrationVault.balanceOf(specificHolder),
                previousBalance,
                1000,
                "Balance should remain the same after upgrade"
            );
            assertEqThreshold(
                migrationVault.previewDepositAsset(MC.SLISBNB, 1e18),
                previousPreviewDeposit,
                1000,
                "Preview deposit asset should remain the same after upgrade"
            );
            assertEqThreshold(
                migrationVault.previewRedeemAsset(MC.SLISBNB, 1e18),
                previousPreviewRedeem,
                1000,
                "Preview redeem asset should remain the same after upgrade"
            );
            assertEqThreshold(
                migrationVault.previewWithdrawAsset(MC.SLISBNB, 1e18),
                previousPreviewWithdraw,
                1000,
                "Preview withdraw asset should remain the same after upgrade"
            );
            // NOTE: preview functions return in base (BNB) after upgrade
            // assertEqThreshold(
            //     migrationVault.previewDeposit(1e18),
            //     previousPreviewDeposit,
            //     1000,
            //     "Preview deposit should remain the same after upgrade"
            // );
            // assertEqThreshold(
            //     migrationVault.previewRedeem(1e18),
            //     previousPreviewRedeem,
            //     1000,
            //     "Preview redeem should remain the same after upgrade"
            // );
            // assertEqThreshold(
            //     migrationVault.previewWithdraw(1e18),
            //     previousPreviewWithdraw,
            //     1000,
            //     "Preview withdraw should remain the same after upgrade"
            // );
        }

        return vault;
    }

    function configureVault(KernelStrategy vault_) internal {
        vm.startPrank(ADMIN);

        vault_.grantRole(vault_.PROCESSOR_ROLE(), PROCESSOR);
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault_.grantRole(vault_.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault_.grantRole(vault_.PAUSER_ROLE(), PAUSER);
        vault_.grantRole(vault_.UNPAUSER_ROLE(), UNPAUSER);

        // set strategy manager to admin for now
        vault_.grantRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), ADMIN);
        vault_.grantRole(vault_.DEPOSIT_MANAGER_ROLE(), ADMIN);
        vault_.grantRole(vault_.ALLOCATOR_MANAGER_ROLE(), ADMIN);

        // set provider
        vault_.setProvider(address(MC.PROVIDER));

        vault_.addAssetWithDecimals(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.WBNB), 18, false);
        vault_.addAssetWithDecimals(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SLISBNB), 18, false);
        vault_.addAssetWithDecimals(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.BNBX), 18, false);

        setApprovalRule(vault_, MC.SLISBNB, MC.STAKER_GATEWAY);
        setStakingRule(vault_, MC.STAKER_GATEWAY, MC.SLISBNB);
        setUnstakingRule(vault, MC.STAKER_GATEWAY, MC.SLISBNB);

        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
    }

    function stakeIntoKernel(address asset) public {
        stakeIntoKernel(asset, IERC20(asset).balanceOf(address(vault)));
    }

    function stakeIntoKernel(address asset, uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = asset;
        targets[1] = MC.STAKER_GATEWAY;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.STAKER_GATEWAY, amount);
        data[1] = abi.encodeWithSignature("stake(address,uint256,string)", asset, amount, "");

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        vault.processAccounting();
    }

    function test_Vault_Upgrade_ERC20_view_functions() public view {
        // Test the name function
        assertEq(
            vault.name(), "YieldNest Restaked BNB - Kernel", "Vault name should be 'YieldNest Restaked BNB - Kernel'"
        );

        // Test the symbol function
        assertEq(vault.symbol(), "ynBNBk", "Vault symbol should be 'ynBNBk'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        vault.totalSupply();
    }

    function test_Vault_Viewer_functions_default() public view {
        BaseVaultViewer.AssetInfo[] memory assets = viewer.getAssets();
        BaseVaultViewer.AssetInfo[] memory underlyingAssets = viewer.getUnderlyingAssets();
        BaseVaultViewer.AssetInfo[] memory availableAssets = viewer.getAvailableUnderlyingAssets();

        assertEq(assets.length, 6, "Should have 6 assets");
        assertEq(underlyingAssets.length, 3, "Should have 3 underlying assets");
        assertEq(availableAssets.length, 3, "Should have 3 available underlying assets");
        assertEq(assets[1].asset, MC.SLISBNB, "Should have SLISBNB as the second asset");
        assertEq(
            assets[4].asset, stakerGateway.getVault(MC.SLISBNB), "Should have SLISBNB as the second underlying asset"
        );

        for (uint256 i = 0; i < 3; i++) {
            assertEq(underlyingAssets[i].asset, assets[i].asset, "Underlying asset should be the same");
            assertEq(underlyingAssets[i].name, assets[i].name, "Underlying asset name should be the same");
            assertEq(underlyingAssets[i].symbol, assets[i].symbol, "Underlying asset symbol should be the same");
            assertEq(underlyingAssets[i].rate, assets[i].rate, "Underlying asset rate should be the same");

            if (underlyingAssets[i].totalBalanceInUnitOfAccount != 0) {
                assertEqThreshold(
                    underlyingAssets[i].ratioOfTotalAssets,
                    assets[i].ratioOfTotalAssets + assets[i + 3].ratioOfTotalAssets,
                    10,
                    "Underlying asset ratioOfTotalAssets should be the same"
                );
                assertEqThreshold(
                    underlyingAssets[i].totalBalanceInUnitOfAccount,
                    assets[i].totalBalanceInUnitOfAccount + assets[i + 3].totalBalanceInUnitOfAccount,
                    10,
                    "Underlying asset totalBalanceInUnitOfAccount should be the same"
                );
                assertEqThreshold(
                    underlyingAssets[i].totalBalanceInAsset,
                    assets[i].totalBalanceInAsset + assets[i + 3].totalBalanceInAsset,
                    10,
                    "Underlying asset totalBalanceInAsset should be the same"
                );
            } else {
                assertEq(
                    underlyingAssets[i].ratioOfTotalAssets, 0, "Underlying asset ratioOfTotalAssets should be the same"
                );
                assertEq(
                    underlyingAssets[i].totalBalanceInUnitOfAccount,
                    0,
                    "Underlying asset totalBalanceInUnitOfAccount should be the same"
                );
                assertEq(
                    underlyingAssets[i].totalBalanceInAsset,
                    0,
                    "Underlying asset totalBalanceInAsset should be the same"
                );
                assertEq(assets[i].ratioOfTotalAssets, 0, "Underlying asset ratioOfTotalAssets should be the same");
                assertEq(
                    assets[i].totalBalanceInUnitOfAccount,
                    0,
                    "Underlying asset totalBalanceInUnitOfAccount should be the same"
                );
                assertEq(assets[i].totalBalanceInAsset, 0, "Underlying asset totalBalanceInAsset should be the same");
                assertEq(assets[i + 3].ratioOfTotalAssets, 0, "Underlying asset ratioOfTotalAssets should be the same");
                assertEq(
                    assets[i + 3].totalBalanceInUnitOfAccount,
                    0,
                    "Underlying asset totalBalanceInUnitOfAccount should be the same"
                );
                assertEq(
                    assets[i + 3].totalBalanceInAsset, 0, "Underlying asset totalBalanceInAsset should be the same"
                );
            }
            assertEq(
                underlyingAssets[i].canDeposit, assets[i].canDeposit, "Underlying asset canDeposit should be the same"
            );
            assertEq(underlyingAssets[i].decimals, assets[i].decimals, "Underlying asset decimals should be the same");

            // availableAssets
            assertEq(underlyingAssets[i].asset, availableAssets[i].asset, "Underlying asset should be the same");
            assertEq(
                underlyingAssets[i].totalBalanceInAsset,
                availableAssets[i].totalBalanceInAsset,
                "Underlying asset should be the same"
            );
            assertEq(
                underlyingAssets[i].totalBalanceInUnitOfAccount,
                availableAssets[i].totalBalanceInUnitOfAccount,
                "Underlying asset should be the same"
            );
            assertEq(
                underlyingAssets[i].canDeposit,
                availableAssets[i].canDeposit,
                "Underlying asset canDeposit should be the same"
            );
            assertEq(
                underlyingAssets[i].decimals,
                availableAssets[i].decimals,
                "Underlying asset decimals should be the same"
            );
        }
    }

    function test_Vault_Viewer_functions_staked() public {
        BaseVaultViewer.AssetInfo[] memory assets = viewer.getAssets();
        uint256 beforeAssetBalance = assets[1].totalBalanceInAsset;
        uint256 beforeVaultBalance = assets[4].totalBalanceInAsset;
        assertEq(beforeVaultBalance, 0, "Should have 0 SLISBNB in vault");

        uint256 stakeAmount = beforeAssetBalance / 2;

        stakeIntoKernel(MC.SLISBNB, stakeAmount);

        assets = viewer.getAssets();
        BaseVaultViewer.AssetInfo[] memory underlyingAssets = viewer.getUnderlyingAssets();
        BaseVaultViewer.AssetInfo[] memory availableAssets = viewer.getAvailableUnderlyingAssets();

        assertEq(assets.length, 6, "Should have 6 assets");
        assertEq(underlyingAssets.length, 3, "Should have 3 underlying assets");
        assertEq(assets[1].asset, MC.SLISBNB, "Should have SLISBNB as the second asset");
        assertEq(
            assets[1 + 3].asset,
            stakerGateway.getVault(MC.SLISBNB),
            "Should have SLISBNB as the second underlying asset"
        );

        uint256 afterAssetBalance = assets[1].totalBalanceInAsset;
        uint256 afterVaultBalance = assets[1 + 3].totalBalanceInAsset;
        assertEqThreshold(afterVaultBalance, beforeAssetBalance / 2, 10, "Should have SLISBNB in vault");
        assertEqThreshold(afterAssetBalance, beforeAssetBalance / 2, 10, "Should have 0 SLISBNB in asset");

        for (uint256 i = 0; i < 3; i++) {
            assertEq(underlyingAssets[i].asset, assets[i].asset, "Underlying asset should be the same");
            assertEq(underlyingAssets[i].name, assets[i].name, "Underlying asset name should be the same");
            assertEq(underlyingAssets[i].symbol, assets[i].symbol, "Underlying asset symbol should be the same");
            assertEq(underlyingAssets[i].rate, assets[i].rate, "Underlying asset rate should be the same");
            if (underlyingAssets[i].totalBalanceInUnitOfAccount != 0) {
                assertEqThreshold(
                    underlyingAssets[i].ratioOfTotalAssets,
                    assets[i].ratioOfTotalAssets + assets[i + 3].ratioOfTotalAssets,
                    10,
                    "Underlying asset ratioOfTotalAssets should be the same"
                );
                assertEqThreshold(
                    underlyingAssets[i].totalBalanceInUnitOfAccount,
                    assets[i].totalBalanceInUnitOfAccount + assets[i + 3].totalBalanceInUnitOfAccount,
                    10,
                    "Underlying asset totalBalanceInUnitOfAccount should be the same"
                );
                assertEqThreshold(
                    underlyingAssets[i].totalBalanceInAsset,
                    assets[i].totalBalanceInAsset + assets[i + 3].totalBalanceInAsset,
                    10,
                    "Underlying asset totalBalanceInAsset should be the same"
                );
            }
            assertEq(
                underlyingAssets[i].canDeposit, assets[i].canDeposit, "Underlying asset canDeposit should be the same"
            );
            assertEq(underlyingAssets[i].decimals, assets[i].decimals, "Underlying asset decimals should be the same");

            // availableAssets
            assertEq(underlyingAssets[i].asset, availableAssets[i].asset, "Underlying asset should be the same");
            assertEq(
                underlyingAssets[i].totalBalanceInAsset,
                availableAssets[i].totalBalanceInAsset,
                "Underlying asset should be the same"
            );
            assertEq(
                underlyingAssets[i].totalBalanceInUnitOfAccount,
                availableAssets[i].totalBalanceInUnitOfAccount,
                "Underlying asset should be the same"
            );
            assertEq(
                underlyingAssets[i].canDeposit,
                availableAssets[i].canDeposit,
                "Underlying asset canDeposit should be the same"
            );
            assertEq(
                underlyingAssets[i].decimals,
                availableAssets[i].decimals,
                "Underlying asset decimals should be the same"
            );
        }

        assertEq(underlyingAssets[1].totalBalanceInAsset, beforeAssetBalance, "Should have SLISBNB in vault");
    }

    function test_Vault_Viewer_functions_staked_sync_withdraw_disabled() public {
        BaseVaultViewer.AssetInfo[] memory assets = viewer.getAssets();
        uint256 beforeAssetBalance = assets[1].totalBalanceInAsset;
        uint256 beforeVaultBalance = assets[4].totalBalanceInAsset;
        assertEq(beforeVaultBalance, 0, "Should have 0 SLISBNB in vault");

        uint256 stakeAmount = beforeAssetBalance / 2;

        stakeIntoKernel(MC.SLISBNB, stakeAmount);

        assets = viewer.getAssets();

        assertEq(assets.length, 6, "Should have 6 assets");
        assertEq(assets[1].asset, MC.SLISBNB, "Should have SLISBNB as the second asset");
        assertEq(
            assets[1 + 3].asset,
            stakerGateway.getVault(MC.SLISBNB),
            "Should have SLISBNB as the second underlying asset"
        );

        uint256 afterAssetBalance = assets[1].totalBalanceInAsset;
        uint256 afterVaultBalance = assets[1 + 3].totalBalanceInAsset;
        assertEqThreshold(afterVaultBalance, beforeAssetBalance / 2, 10, "Should have SLISBNB in vault");
        assertEqThreshold(afterAssetBalance, beforeAssetBalance / 2, 10, "Should have 0 SLISBNB in asset");

        vm.prank(ADMIN);
        vault.setSyncWithdraw(false);

        BaseVaultViewer.AssetInfo[] memory underlyingAssets = viewer.getUnderlyingAssets();
        BaseVaultViewer.AssetInfo[] memory availableAssets = viewer.getAvailableUnderlyingAssets();

        uint256 i = 1;

        assertEq(underlyingAssets[i].asset, availableAssets[i].asset, "Underlying asset should be the same");

        assertEqThreshold(
            underlyingAssets[i].ratioOfTotalAssets,
            1000000,
            10,
            "Underlying asset ratioOfTotalAssets should be the correct"
        );
        assertEqThreshold(
            availableAssets[i].ratioOfTotalAssets,
            500000,
            10,
            "Available asset ratioOfTotalAssets should be the correct"
        );
        assertEqThreshold(
            underlyingAssets[i].totalBalanceInAsset,
            availableAssets[i].totalBalanceInAsset * 2,
            10,
            "Should have SLISBNB in vault"
        );
        assertEqThreshold(
            underlyingAssets[i].totalBalanceInAsset,
            availableAssets[i].totalBalanceInAsset * 2,
            10,
            "Should have SLISBNB in vault"
        );
        assertEqThreshold(
            underlyingAssets[i].totalBalanceInUnitOfAccount,
            availableAssets[i].totalBalanceInUnitOfAccount * 2,
            10,
            "Should have SLISBNB in vault"
        );
    }

    function test_Vault_Upgrade_ERC4626_view_functions() public view {
        // Test the paused function
        assertFalse(vault.paused(), "Vault should not be paused");

        // Test the asset function
        assertEq(address(vault.asset()), MC.WBNB, "Vault asset should be WBNB");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        assertGe(totalAssets, totalSupply, "TotalAssets should be greater than totalSupply");

        // Test the convertToShares function
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);
        assertLe(shares, amount, "Shares should be less or equal to amount deposited");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertEqThreshold(convertedAssets, amount, 10, "Converted assets should be close to amount deposited");

        // Test the maxDeposit function
        uint256 maxDeposit = vault.maxDeposit(address(this));
        assertGt(maxDeposit, 0, "Max deposit should be greater than 0");

        // Test the maxMint function
        uint256 maxMint = vault.maxMint(address(this));
        assertGt(maxMint, 0, "Max mint should be greater than 0");

        // Test the maxWithdraw function
        uint256 maxWithdraw = vault.maxWithdraw(address(this));
        assertEq(maxWithdraw, 0, "Max withdraw should be zero");

        // Test the maxRedeem function
        uint256 maxRedeem = vault.maxRedeem(address(this));
        assertEq(maxRedeem, 0, "Max redeem should be zero");

        // Test the getAssets function
        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 6, "There should be six assets in the vault");
        assertEq(assets[0], MC.WBNB, "First asset should be WBNB");
        assertEq(assets[1], MC.SLISBNB, "Second asset should be SLISBNB");
        assertEq(assets[2], MC.BNBX, "Third asset should be SLISBNB");

        shares = vault.previewWithdrawAsset(MC.SLISBNB, amount);
        convertedAssets = vault.previewRedeemAsset(MC.SLISBNB, shares);

        assertEqThreshold(convertedAssets, amount, 10, "Converted assets should be equal to amount");
    }

    function test_Vault_ynBNBk_view_functions() public view {
        bool syncDeposit = vault.getSyncDeposit();
        assertTrue(syncDeposit, "SyncDeposit should be true");

        bool syncWithdraw = vault.getSyncWithdraw();
        assertTrue(syncWithdraw, "SyncWithdraw should be true");

        address strategyGateway = vault.getStakerGateway();
        assertEq(strategyGateway, MC.STAKER_GATEWAY, "incorrect staker gateway");
    }

    function depositIntoVault(address assetAddress, uint256 amount) internal returns (uint256 shares) {
        return depositIntoVault(assetAddress, amount, true);
    }

    function depositIntoVault(address assetAddress, uint256 amount, bool syncDeposit)
        internal
        returns (uint256 shares)
    {
        IERC20 asset = IERC20(assetAddress);

        vm.prank(ADMIN);
        vault.setSyncDeposit(syncDeposit);

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SLISBNB);

        uint256 beforeTotalAssets = vault.totalAssets();
        uint256 beforeTotalShares = vault.totalSupply();
        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeKernelVaultBalance = asset.balanceOf(kernelVault);
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);
        {
            uint256 beforeMaxWithdraw = viewer.maxWithdrawAsset(address(asset), bob);
            assertEq(beforeMaxWithdraw, 0, "Bob should have no max withdraw before deposit");

            {
                uint256 previewShares = vault.previewDepositAsset(assetAddress, amount);

                vm.prank(bob);
                asset.approve(address(vault), amount);

                // Test the deposit function
                vm.prank(bob);
                shares = vault.depositAsset(assetAddress, amount, bob);

                vault.processAccounting();

                assertEq(previewShares, shares, "Preview shares should be equal to shares");
            }
            assertEqThreshold(
                viewer.maxWithdrawAsset(assetAddress, bob),
                beforeMaxWithdraw + amount,
                5,
                "maxWithdrawAsset should be correct"
            );
        }

        uint256 assetsInBNB = vault.convertToAssets(shares);

        assertEqThreshold(
            vault.totalAssets(),
            beforeTotalAssets + assetsInBNB,
            10,
            "Total assets should increase by the amount deposited"
        );
        assertEq(
            vault.totalSupply(), beforeTotalShares + shares, "Total shares should increase by the amount deposited"
        );
        if (syncDeposit) {
            assertEq(
                asset.balanceOf(address(vault)), beforeVaultBalance, "Vault should not have the asset after deposit"
            );
            assertEq(
                asset.balanceOf(kernelVault),
                beforeKernelVaultBalance + amount,
                "KernelVault should have the asset after deposit"
            );
        } else {
            assertEq(
                asset.balanceOf(address(vault)),
                beforeVaultBalance + amount,
                "Vault should have the asset after deposit"
            );
            assertEq(
                asset.balanceOf(kernelVault),
                beforeKernelVaultBalance,
                "KernelVault should not have the asset after deposit"
            );
        }
        assertEq(asset.balanceOf(bob), beforeBobBalance - amount, "Bob should not have the assets");
        assertEq(vault.balanceOf(bob), beforeBobShares + shares, "Bob should have shares after deposit");

        return shares;
    }

    function getSlisBnb(uint256 amount) internal {
        // deposit BNB to SLISBNB through stake manager
        ISlisBnbStakeManager stakeManager = ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER);

        vm.deal(bob, amount * 2);

        vm.prank(bob);
        stakeManager.deposit{value: amount * 2}();

        IERC20 slisBnb = IERC20(MC.SLISBNB);
        assertGe(slisBnb.balanceOf(bob), amount, "Should have slisBnb");
    }

    function test_Vault_ynBNBk_deposit_slisBNB_sync_deposit_enabled(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);

        IERC20 asset = IERC20(MC.SLISBNB);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeKernelVaultBalance = stakerGateway.balanceOf(address(asset), address(vault));
        uint256 previewShares = vault.previewDepositAsset(address(asset), amount);
        uint256 beforeMaxWithdraw = viewer.maxWithdrawAsset(address(asset), bob);
        assertEq(beforeMaxWithdraw, 0, "Bob should have no max withdraw");

        getSlisBnb(amount);

        vm.prank(bob);
        asset.approve(address(vault), amount);

        // Test the deposit function
        vm.prank(bob);
        uint256 shares = vault.depositAsset(address(asset), amount, bob);

        assertEq(previewShares, shares, "Preview shares should be equal to shares");
        assertEq(asset.balanceOf(address(vault)), beforeVaultBalance, "Vault should not have the asset after deposit");
        assertEqThreshold(
            stakerGateway.balanceOf(address(asset), address(vault)),
            beforeKernelVaultBalance + amount,
            100,
            "Vault should have a balance in the Kernel StakerGateway"
        );
        assertEqThreshold(
            viewer.maxWithdrawAsset(address(asset), bob),
            beforeMaxWithdraw + amount,
            5,
            "Bob should have max withdraw after deposit"
        );
    }

    function test_Vault_ynBNBk_deposit_slisBNB_sync_deposit_disabled(uint256 amount) public {
        //set sync deposit disabled
        vm.prank(ADMIN);
        vault.setSyncDeposit(false);

        amount = bound(amount, 10, 100_000 ether);

        IERC20 asset = IERC20(MC.SLISBNB);

        uint256 beforeVaultStakerBalance = stakerGateway.balanceOf(address(asset), address(vault));
        uint256 beforeVaultSlisBalance = asset.balanceOf(address(vault));

        getSlisBnb(amount);

        vm.prank(bob);
        asset.approve(address(vault), amount);

        // Test the deposit function
        vm.prank(bob);
        vault.depositAsset(address(asset), amount, bob);

        assertEq(
            stakerGateway.balanceOf(address(asset), address(vault)),
            beforeVaultStakerBalance,
            "Vault should have a balance in the stakerGateway"
        );
        assertEq(
            asset.balanceOf(address(vault)), beforeVaultSlisBalance + amount, "vault should have a balance of amount"
        );

        // process deposit
        uint256 vaultBalance = IERC20(asset).balanceOf(address(vault));

        stakeIntoKernel(address(asset));
        // check balances
        assertEqThreshold(
            stakerGateway.balanceOf(address(asset), address(vault)),
            beforeVaultStakerBalance + vaultBalance,
            100,
            "Vault should have a balance in the stakerGateway"
        );
        assertEq(asset.balanceOf(address(vault)), 0, "vault should have no balance");
    }

    function test_Vault_ynBNBk_withdraw_slisBNB_sync_deposit_disabled(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);

        getSlisBnb(amount);

        depositIntoVault(MC.SLISBNB, amount);
        stakeIntoKernel(MC.SLISBNB);
        IERC20 asset = IERC20(MC.SLISBNB);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);
        uint256 beforeVaultStakerShares = stakerGateway.balanceOf(address(asset), address(vault));

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.SLISBNB, bob);
        assertEqThreshold(maxWithdraw, amount, 5, "Max withdraw should be equal to amount");

        uint256 previewShares = vault.previewWithdrawAsset(MC.SLISBNB, maxWithdraw);

        vm.prank(bob);
        uint256 shares = vault.withdrawAsset(MC.SLISBNB, maxWithdraw, bob, bob);

        assertEq(shares, previewShares, "Shares should be equal to preview shares");

        uint256 afterVaultBalance = asset.balanceOf(address(vault));
        uint256 afterBobBalance = asset.balanceOf(bob);
        uint256 afterBobShares = vault.balanceOf(bob);
        uint256 afterVaultStakerShares = stakerGateway.balanceOf(address(asset), address(vault));

        assertEq(afterVaultBalance, beforeVaultBalance, "Vault balance should decrease be 0");
        assertEq(afterBobBalance, beforeBobBalance + maxWithdraw, "Bob balance should increase by maxWithdraw");
        assertEq(afterBobShares, beforeBobShares - shares, "Bob shares should decrease by shares");
        assertEq(
            afterVaultStakerShares,
            beforeVaultStakerShares - maxWithdraw,
            "Vault shares should decrease after withdrawal"
        );
    }

    function test_Vault_ynBNBk_withdraw_slisBNB_sync_enabled_unstake_only_enough(uint256 amount) public {
        amount = bound(amount, 20, 100_000 ether);

        IERC20 asset = IERC20(MC.SLISBNB);
        getSlisBnb(amount);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeKernelBalance = stakerGateway.balanceOf(address(asset), address(vault));
        assertEq(beforeKernelBalance, 0, "Kernel should have no balance");
        stakeIntoKernel(MC.SLISBNB);
        assertEq(asset.balanceOf(address(vault)), 0, "Vault should have no balance");
        assertEq(
            stakerGateway.balanceOf(address(asset), address(vault)),
            beforeVaultBalance,
            "Kernel should have all balance"
        );

        depositIntoVault(MC.SLISBNB, amount, false);
        stakeIntoKernel(MC.SLISBNB, amount / 2);

        assertEqThreshold(asset.balanceOf(address(vault)), amount / 2, 5, "Vault should have half balance");
        assertEqThreshold(
            stakerGateway.balanceOf(address(asset), address(vault)),
            beforeVaultBalance + amount / 2,
            5,
            "Kernel should have half balance"
        );

        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.SLISBNB, bob);
        assertEqThreshold(maxWithdraw, amount, 5, "Max withdraw should be equal to amount");

        uint256 withdrawAmount = 3 * amount / 4; // withdraw 3/4 of the amount
        vm.prank(bob);
        uint256 shares = vault.withdrawAsset(MC.SLISBNB, withdrawAmount, bob, bob);

        uint256 afterVaultBalance = asset.balanceOf(address(vault));
        uint256 afterKernelBalance = stakerGateway.balanceOf(address(asset), address(vault));
        uint256 afterBobBalance = asset.balanceOf(bob);
        uint256 afterBobShares = vault.balanceOf(bob);

        assertEq(afterVaultBalance, 0, "Vault balance should decrease be 0");
        assertEqThreshold(
            afterKernelBalance, beforeVaultBalance + amount / 4, 5, "Kernel balance should decrease by amount / 4"
        );
        assertEqThreshold(
            afterBobBalance, beforeBobBalance + withdrawAmount, 5, "Bob balance should increase by maxWithdraw"
        );
        assertEq(afterBobShares, beforeBobShares - shares, "Bob shares should decrease by shares");
    }

    function test_Vault_ynBNBk_withdraw_slisBNB_sync_disabled(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);

        IERC20 asset = IERC20(MC.SLISBNB);

        // disable withdraw sync
        vm.prank(ADMIN);
        vault.setSyncWithdraw(false);

        // get slis
        getSlisBnb(amount);

        // deposit asset
        depositIntoVault(address(asset), amount, false);

        // stake slis
        stakeIntoKernel(address(asset));

        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);
        uint256 maxAssets = vault.previewRedeemAsset(MC.SLISBNB, beforeBobShares);

        vm.prank(bob);
        vm.expectRevert();
        uint256 shares = vault.withdrawAsset(MC.SLISBNB, maxAssets, bob, bob);

        assertEq(shares, 0, "Shares should be 0");

        assertEq(asset.balanceOf(address(vault)), 0, "Vault balance should be 0");
        assertEq(asset.balanceOf(bob), beforeBobBalance, "Bob balance should not increase");
        assertEq(vault.balanceOf(bob), beforeBobShares, "Bob shares should not decrease");

        vault.processAccounting();

        assertEq(asset.balanceOf(address(vault)), 0, "Vault balance should be 0");
        assertEq(asset.balanceOf(bob), beforeBobBalance, "Bob balance should not increase");
        assertEq(vault.balanceOf(bob), beforeBobShares, "Bob shares should not decrease");

        address[] memory targets = new address[](1);
        targets[0] = MC.STAKER_GATEWAY;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("unstake(address,uint256,string)", address(asset), amount, "");

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        vault.processAccounting();

        assertEq(asset.balanceOf(address(vault)), amount, "Vault balance should be amount");
        assertEq(asset.balanceOf(bob), beforeBobBalance, "Bob balance should not increase");
        assertEq(vault.balanceOf(bob), beforeBobShares, "Bob shares should not decrease");

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.SLISBNB, bob);

        assertEqThreshold(maxWithdraw, amount, 5, "maxWithdraw should be equal to amount");

        // withdraw for real
        vm.prank(bob);
        shares = vault.withdrawAsset(MC.SLISBNB, maxWithdraw, bob, bob);

        assertEq(asset.balanceOf(address(vault)), amount - maxWithdraw, "Vault balance should be 0");
        assertEq(asset.balanceOf(bob), beforeBobBalance + maxWithdraw, "Bob balance should increase");
        assertEq(vault.balanceOf(bob), beforeBobShares - shares, "Bob shares should decrease");
    }

    function test_Vault_ynBNBk_redeem_slisBNB(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);

        getSlisBnb(amount);

        IERC20 asset = IERC20(MC.SLISBNB);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 shares = depositIntoVault(MC.SLISBNB, amount, false);

        uint256 maxRedeem = vault.maxRedeemAsset(MC.SLISBNB, bob);
        uint256 previewAssets = vault.previewRedeemAsset(MC.SLISBNB, maxRedeem);

        assertEqThreshold(maxRedeem, shares, 5, "Max redeem should be equal to shares");

        assertGt(asset.balanceOf(address(vault)), previewAssets, "Vault should have enough assets to withdraw");

        vm.prank(bob);
        uint256 assets = vault.redeemAsset(MC.SLISBNB, maxRedeem, bob, bob);

        assertEq(previewAssets, assets, "Preview assets should be equal to assets");

        assertEqThreshold(assets, amount, 10, "Assets should be close to amount");

        assertEq(
            asset.balanceOf(address(vault)),
            beforeVaultBalance + amount - assets,
            "Vault should have transferred the asset to bob"
        );
        assertEq(
            asset.balanceOf(bob),
            beforeBobBalance - amount + assets,
            "Bob should have the amount deposited after withdraw"
        );
        assertEqThreshold(vault.balanceOf(bob), beforeBobShares, 5, "Bob should have no shares after withdraw");
    }

    function test_Vault_ynBNBk_deposit_and_stake_slisBNB(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);

        getSlisBnb(amount);

        depositIntoVault(MC.SLISBNB, amount, false);

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SLISBNB);

        IERC20 asset = IERC20(MC.SLISBNB);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeKernelVaultBalance = asset.balanceOf(kernelVault);
        uint256 beforeTotalAssets = vault.totalAssets();

        stakeIntoKernel(MC.SLISBNB);

        assertEq(asset.balanceOf(address(vault)), 0, "Vault should have the asset after deposit");
        assertEq(
            asset.balanceOf(kernelVault),
            beforeKernelVaultBalance + beforeVaultBalance,
            "KernelVault should have the asset after deposit"
        );
        assertEq(vault.totalAssets(), beforeTotalAssets, "Total assets should not change");
    }

    function test_Vault_ynBNBk_deposit_and_stake_and_withdraw_slisBNB(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);

        getSlisBnb(amount);

        depositIntoVault(MC.SLISBNB, amount, false);

        IERC20 asset = IERC20(MC.SLISBNB);

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SLISBNB);

        {
            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeKernelVaultBalance = asset.balanceOf(kernelVault);
            uint256 beforeTotalAssets = vault.totalAssets();

            stakeIntoKernel(MC.SLISBNB);

            assertEq(asset.balanceOf(address(vault)), 0, "Vault should have the asset after deposit");
            assertEq(
                asset.balanceOf(kernelVault),
                beforeKernelVaultBalance + beforeVaultBalance,
                "KernelVault should have the asset after deposit"
            );
            assertEqThreshold(vault.totalAssets(), beforeTotalAssets, 10, "Total assets should not change");
        }

        {
            uint256 beforeKernelVaultBalance = asset.balanceOf(kernelVault);
            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeBobBalance = asset.balanceOf(bob);
            uint256 beforeBobShares = vault.balanceOf(bob);

            uint256 assets = vault.previewRedeemAsset(MC.SLISBNB, beforeBobShares);

            vm.prank(bob);
            uint256 shares = vault.withdrawAsset(MC.SLISBNB, assets, bob, bob);

            uint256 afterKernelVaultBalance = asset.balanceOf(kernelVault);
            uint256 afterVaultBalance = asset.balanceOf(address(vault));
            uint256 afterBobBalance = asset.balanceOf(bob);
            uint256 afterBobShares = vault.balanceOf(bob);

            assertEq(
                afterKernelVaultBalance,
                beforeKernelVaultBalance - assets,
                "KernelVault balance should decrease by assets"
            );
            assertEq(afterVaultBalance, beforeVaultBalance, "Vault balance should remain same");
            assertEq(afterBobBalance, beforeBobBalance + assets, "Bob balance should increase by assets");
            assertEq(afterBobShares, beforeBobShares - shares, "Bob shares should decrease by shares");
        }
    }

    function test_Vault_ynBNBk_deposit_and_stake_and_redeem_slisBNB(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);

        getSlisBnb(amount);

        depositIntoVault(MC.SLISBNB, amount, false);

        IERC20 asset = IERC20(MC.SLISBNB);

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SLISBNB);

        {
            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeKernelVaultBalance = asset.balanceOf(kernelVault);
            uint256 beforeTotalAssets = vault.totalAssets();

            stakeIntoKernel(MC.SLISBNB);

            assertEq(asset.balanceOf(address(vault)), 0, "Vault should have the asset after deposit");
            assertEq(
                asset.balanceOf(kernelVault),
                beforeKernelVaultBalance + beforeVaultBalance,
                "KernelVault should have the asset after deposit"
            );
            assertEqThreshold(vault.totalAssets(), beforeTotalAssets, 10, "Total assets should not change");
        }

        {
            uint256 beforeKernelVaultBalance = asset.balanceOf(kernelVault);
            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeBobBalance = asset.balanceOf(bob);
            uint256 beforeBobShares = vault.balanceOf(bob);

            uint256 maxRedeem = vault.maxRedeemAsset(MC.SLISBNB, bob);
            uint256 previewAssets = vault.previewRedeemAsset(MC.SLISBNB, maxRedeem);

            assertEqThreshold(maxRedeem, beforeBobShares, 5, "Max redeem should be equal to shares");

            vm.prank(bob);
            uint256 assets = vault.redeemAsset(MC.SLISBNB, maxRedeem, bob, bob);

            assertEq(previewAssets, assets, "Preview assets should be equal to assets");

            uint256 afterKernelVaultBalance = asset.balanceOf(kernelVault);
            uint256 afterVaultBalance = asset.balanceOf(address(vault));
            uint256 afterBobBalance = asset.balanceOf(bob);
            uint256 afterBobShares = vault.balanceOf(bob);

            assertEq(
                afterKernelVaultBalance,
                beforeKernelVaultBalance - assets,
                "KernelVault balance should decrease by assets"
            );
            assertEq(afterVaultBalance, beforeVaultBalance, "Vault balance should remain same");
            assertEq(afterBobBalance, beforeBobBalance + assets, "Bob balance should increase by assets");
            assertEqThreshold(afterBobShares, 0, 5, "Bob shares should decrease by shares");
        }
    }
}
