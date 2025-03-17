// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

import {IERC20, Math} from "lib/yieldnest-vault/src/Common.sol";

import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetKernelActors} from "script/KernelActors.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {BaseVaultViewer, KernelVaultViewer} from "src/utils/KernelVaultViewer.sol";

import {VaultUtils} from "lib/yieldnest-vault/script/VaultUtils.sol";

import {VaultKernelUtils} from "script/VaultKernelUtils.sol";
import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {BTCRateProvider} from "src/module/BTCRateProvider.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";

contract YnBTCkTest is Test, AssertUtils, MainnetKernelActors, EtchUtils, VaultUtils, VaultKernelUtils {
    KernelStrategy public vault;
    BTCRateProvider public kernelProvider;
    IStakerGateway public stakerGateway;
    KernelVaultViewer public viewer;

    address public bob = address(0xB0B);

    IERC20 public cobtc;

    function setUp() public {
        kernelProvider = new BTCRateProvider();
        etchProvider(address(kernelProvider));

        stakerGateway = IStakerGateway(MC.STAKER_GATEWAY);

        vault = deploy();
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

        vm.label(MC.STAKER_GATEWAY, "kernel staker gateway");
        vm.label(address(vault), "kernel strategy");
        vm.label(address(kernelProvider), "kernel rate provider");

        cobtc = IERC20(MC.COBTC);

        mockDepositLimit();
    }

    function mockDepositLimit() public {
        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.COBTC);
        address config = IKernelVault(kernelVault).getConfig();
        bytes32 role = IKernelConfig(config).ROLE_MANAGER();

        vm.prank(MC.KERNEL_CONFIG_ADMIN);
        IKernelConfig(config).grantRole(role, address(this));

        IKernelVault(kernelVault).setDepositLimit(type(uint256).max);

        assertEq(IKernelVault(kernelVault).getDepositLimit(), type(uint256).max, "Deposit limit should be max");
    }

    function deploy() public returns (KernelStrategy _vault) {
        KernelStrategy implementation = new KernelStrategy();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(ADMIN), "");

        _vault = KernelStrategy(payable(address(proxy)));
        _vault.initialize(ADMIN, "YieldNest Restaked Coffer BTC - Kernel", "ynCoBTCk", 18, 0, false, true);

        configureKernelStrategy(_vault);
    }

    function configureKernelStrategy(KernelStrategy vault_) public {
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

        vault_.setProvider(address(kernelProvider));

        vault_.setStakerGateway(MC.STAKER_GATEWAY);

        vault_.setSyncDeposit(true);
        vault_.setSyncWithdraw(true);
        vault_.setHasAllocator(false);

        vault_.addAsset(MC.COBTC, true);
        vault_.setAssetWithdrawable(MC.COBTC, true);
        // VERY IMPORTANT: COBTC has 8 decimals
        vault_.addAssetWithDecimals(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.COBTC), 8, false);

        // set deposit rules
        setApprovalRule(vault_, MC.COBTC, MC.STAKER_GATEWAY);
        setStakingRule(vault_, MC.STAKER_GATEWAY, MC.COBTC);
        setUnstakingRule(vault_, MC.STAKER_GATEWAY, MC.COBTC);

        vault_.unpause();

        vm.stopPrank();

        // No need to call processAccounting here, since alwaysComputeTotalAssets is true
        // vault_.processAccounting();
    }

    function stakeIntoKernel(address asset) public {
        uint256 amount = IERC20(asset).balanceOf(address(vault));

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

        // vault.processAccounting();
    }

    function test_Vault_Upgrade_ERC20_view_functions() public view {
        // Test the name function
        assertEq(
            vault.name(),
            "YieldNest Restaked Coffer BTC - Kernel",
            "Vault name should be 'YieldNest Restaked Coffer BTC - Kernel'"
        );

        // Test the symbol function
        assertEq(vault.symbol(), "ynCoBTCk", "Vault symbol should be 'ynCoBTCk'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        vault.totalSupply();
    }

    function test_Vault_Upgrade_ERC4626_view_functions() public view {
        // Test the paused function
        assertFalse(vault.paused(), "Vault should not be paused");

        // Test the asset function
        assertEq(address(vault.asset()), MC.COBTC, "Vault asset should be BTCB");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        assertGe(totalAssets, totalSupply, "TotalAssets should be greater than totalSupply");

        // Test the convertToShares function
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);

        uint256 rate = IProvider(vault.provider()).getRate(MC.COBTC);
        assertEq(rate, 1e18, "Rate should be 1e18");

        uint256 baseAssets = Math.mulDiv(amount, rate, 10 ** 8, Math.Rounding.Floor);
        uint256 expectedShares = baseAssets;

        assertEq(shares, expectedShares, "Shares should be as expected");

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
        assertEq(assets.length, 2, "There should be six assets in the vault");
        assertEq(assets[0], MC.COBTC, "First asset should be BTCB");

        // Test the getAsset function
        assertEq(vault.getAsset(MC.COBTC).decimals, 8, "Asset decimals should be 8");
        assertEq(vault.getAsset(MC.COBTC).active, true, "Asset should be active");
        assertEq(vault.getAsset(MC.COBTC).index, 0, "Asset index should be 0");

        shares = vault.previewWithdrawAsset(MC.COBTC, amount);
        convertedAssets = vault.previewRedeemAsset(MC.COBTC, shares);

        assertEqThreshold(convertedAssets, amount, 10, "Converted assets should be equal to amount");
    }

    function test_Vault_ynCoBTCk_view_functions() public view {
        bool syncDeposit = vault.getSyncDeposit();
        assertTrue(syncDeposit, "SyncDeposit should be true");

        bool syncWithdraw = vault.getSyncWithdraw();
        assertTrue(syncWithdraw, "SyncWithdraw should be true");

        address strategyGateway = vault.getStakerGateway();
        assertEq(strategyGateway, MC.STAKER_GATEWAY, "incorrect staker gateway");
    }

    function depositIntoVault(address assetAddress, uint256 amount) internal returns (uint256) {
        IERC20 asset = IERC20(assetAddress);

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(assetAddress);

        uint256 beforeTotalAssets = vault.totalAssets();
        uint256 beforeTotalShares = vault.totalSupply();
        uint256 beforeVaultBalance = asset.balanceOf(address(kernelVault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);
        uint256 beforeMaxWithdraw = viewer.maxWithdrawAsset(address(asset), bob);
        assertEq(beforeMaxWithdraw, 0, "Bob should have no max withdraw before deposit");

        uint256 previewShares = vault.previewDepositAsset(assetAddress, amount);

        vm.prank(bob);
        asset.approve(address(vault), amount);

        // Test the deposit function
        vm.prank(bob);
        uint256 shares = vault.depositAsset(assetAddress, amount, bob);

        assertEq(previewShares, shares, "Preview shares should be equal to shares");

        uint256 assetsInCoBTC = vault.convertToAssets(shares);
        uint256 assetsInBase = Math.mulDiv(assetsInCoBTC, 10 ** 18, 10 ** 8, Math.Rounding.Floor);

        assertEqThreshold(
            vault.totalAssets(),
            beforeTotalAssets + assetsInBase,
            10,
            "Total assets should increase by the amount deposited"
        );
        assertEq(
            vault.totalSupply(), beforeTotalShares + shares, "Total shares should increase by the amount deposited"
        );

        assertEq(
            asset.balanceOf(address(kernelVault)),
            beforeVaultBalance + amount,
            "Vault should have the asset after deposit"
        );
        assertEq(asset.balanceOf(bob), beforeBobBalance - amount, "Bob should not have the assets");
        assertEq(vault.balanceOf(bob), beforeBobShares + shares, "Bob should have shares after deposit");
        assertEq(
            viewer.maxWithdrawAsset(address(asset), bob),
            beforeMaxWithdraw + amount,
            "Bob should have max withdraw after deposit"
        );

        return shares;
    }

    function test_Vault_ynCoBTCk_deposit_COBTC(uint256 amount) public {
        amount = bound(amount, 10, 10_000 ether);

        IERC20 asset = IERC20(MC.COBTC);

        //set sync deposit enabled
        vm.prank(ADMIN);
        vault.setSyncDeposit(true);

        uint256 beforeVaultBalance = stakerGateway.balanceOf(address(asset), address(vault));
        uint256 previewShares = vault.previewDepositAsset(address(asset), amount);

        deal(MC.COBTC, bob, amount);

        vm.prank(bob);
        asset.approve(address(vault), amount);

        // Test the deposit function
        vm.prank(bob);
        uint256 shares = vault.depositAsset(address(asset), amount, bob);

        assertEq(previewShares, shares, "Preview shares should be equal to shares");
        assertEqThreshold(
            stakerGateway.balanceOf(address(asset), address(vault)),
            beforeVaultBalance + amount,
            100,
            "Vault should have a balance in the stakerGateway"
        );
    }

    function test_Vault_ynCoBTCk_withdraw_COBTC(uint256 amount) public {
        amount = bound(amount, 10, 10_000 ether);

        deal(MC.COBTC, bob, amount);

        depositIntoVault(MC.COBTC, amount);
        IERC20 asset = IERC20(MC.COBTC);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);
        uint256 beforeVaultStakerShares = stakerGateway.balanceOf(address(asset), address(vault));

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.COBTC, bob);
        assertEqThreshold(maxWithdraw, amount, 2, "Max withdraw should be equal to amount");

        uint256 previewShares = vault.previewWithdrawAsset(MC.COBTC, maxWithdraw);

        vm.prank(bob);
        uint256 shares = vault.withdrawAsset(MC.COBTC, maxWithdraw, bob, bob);

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

    function test_Vault_ynCoBTCk_redeem_COBTC(uint256 amount) public {
        amount = bound(amount, 10, 10_000 ether);

        deal(MC.COBTC, bob, amount);

        IERC20 asset = IERC20(MC.COBTC);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 shares = depositIntoVault(MC.COBTC, amount);

        uint256 previewAssets = vault.previewRedeemAsset(MC.COBTC, shares);

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.COBTC);
        assertGe(asset.balanceOf(address(kernelVault)), previewAssets, "Vault should have enough assets to withdraw");

        vm.prank(bob);
        uint256 assets = vault.redeemAsset(MC.COBTC, shares, bob, bob);

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
        assertEq(vault.balanceOf(bob), beforeBobShares, "Bob should have no shares after withdraw");
    }

    function test_Vault_ynCoBTCk_rewards_COBTC(uint256 amount, uint256 rewards) public {
        amount = bound(amount, 1000, 10_000 ether);
        rewards = bound(rewards, 10, amount / 10);

        deal(MC.COBTC, bob, amount);

        depositIntoVault(MC.COBTC, amount);

        uint256 rewardsForBob = rewards * vault.balanceOf(bob) / vault.totalSupply();

        {
            uint256 beforeAssets = vault.totalAssets();
            uint256 beforeShares = vault.totalSupply();
            uint256 beforeMaxWithdraw = viewer.maxWithdrawAsset(address(MC.COBTC), bob);
            uint256 beforeBobShares = vault.balanceOf(bob);

            deal(MC.COBTC, bob, rewards);

            vm.prank(bob);
            cobtc.transfer(address(vault), rewards);

            // vault.processAccounting();

            uint256 afterAssets = vault.totalAssets();
            uint256 afterMaxWithdraw = viewer.maxWithdrawAsset(address(MC.COBTC), bob);

            assertEq(afterAssets, beforeAssets + rewards * 10 ** 10, "Total assets should increase by rewards");
            assertEq(vault.totalSupply(), beforeShares, "Total shares should not change");
            assertEqThreshold(
                afterMaxWithdraw, beforeMaxWithdraw + rewardsForBob, 10, "Max withdraw should increase by rewards"
            );
            assertEq(vault.balanceOf(bob), beforeBobShares, "Bob should have same shares");
        }

        {
            IERC20 asset = IERC20(MC.COBTC);

            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeBobBalance = asset.balanceOf(bob);
            uint256 beforeBobShares = vault.balanceOf(bob);
            uint256 beforeVaultStakerShares = stakerGateway.balanceOf(address(asset), address(vault));

            uint256 maxWithdraw = vault.maxWithdrawAsset(MC.COBTC, bob);
            assertEqThreshold(maxWithdraw, amount + rewardsForBob, 10, "Max withdraw should be equal to amount");

            uint256 previewShares = vault.previewWithdrawAsset(MC.COBTC, maxWithdraw);

            vm.prank(bob);
            uint256 shares = vault.withdrawAsset(MC.COBTC, maxWithdraw, bob, bob);

            assertEq(shares, previewShares, "Shares should be equal to preview shares");

            uint256 afterVaultBalance = asset.balanceOf(address(vault));
            uint256 afterBobBalance = asset.balanceOf(bob);
            uint256 afterBobShares = vault.balanceOf(bob);
            uint256 afterVaultStakerShares = stakerGateway.balanceOf(address(asset), address(vault));

            assertEq(afterBobBalance, beforeBobBalance + maxWithdraw, "Bob balance should increase by maxWithdraw");
            assertEq(afterBobShares, beforeBobShares - shares, "Bob shares should decrease by shares");

            if (rewards < maxWithdraw) {
                assertEq(afterVaultBalance, 0, "Vault balance should be 0");
                assertEq(
                    afterVaultStakerShares,
                    beforeVaultStakerShares - (maxWithdraw - rewards),
                    "Vault shares should decrease after withdrawal"
                );
            } else {
                assertEq(afterVaultBalance, beforeVaultBalance - maxWithdraw, "Vault balance should decrease");
                assertEq(afterVaultStakerShares, beforeVaultStakerShares, "Vault shares should not change");
            }
        }
    }
}
