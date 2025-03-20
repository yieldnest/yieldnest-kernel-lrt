// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {BeaconProxy} from "lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

import {IERC20Metadata as IERC20, Math} from "lib/yieldnest-vault/src/Common.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetKernelActors} from "script/KernelActors.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {BaseVaultViewer, KernelVaultViewer} from "src/utils/KernelVaultViewer.sol";

import {VaultUtils} from "lib/yieldnest-vault/script/VaultUtils.sol";

import {VaultKernelUtils} from "script/VaultKernelUtils.sol";

import {IAssetRegistry} from "src/interface/external/kernel/IAssetRegistry.sol";
import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {IBFBTC} from "src/interface/external/bitfi/IBFBTC.sol";
import {BfBTCRateProvider} from "src/module/BfBTCRateProvider.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";

contract YnBitFiBTCkTest is Test, MainnetKernelActors, EtchUtils, VaultUtils, VaultKernelUtils {
    using Math for uint256;

    KernelStrategy public vault;
    BfBTCRateProvider public kernelProvider;
    IStakerGateway public stakerGateway;
    IKernelConfig public kernelConfig;
    IAssetRegistry public assetRegistry;
    KernelVaultViewer public viewer;

    address public bob = address(0xB0B);

    uint256 public bfbtcMinDepositAmount;

    IBFBTC public bfbtc;

    function setUp() public {
        kernelProvider = new BfBTCRateProvider();
        etchProvider(address(kernelProvider));

        stakerGateway = IStakerGateway(MC.STAKER_GATEWAY);
        kernelConfig = IKernelConfig(stakerGateway.getConfig());
        assetRegistry = IAssetRegistry(kernelConfig.getAssetRegistry());

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

        bfbtc = IBFBTC(MC.BFBTC);

        bfbtcMinDepositAmount = bfbtc.minDepositTokenAmount();
    }

    function deploy() public returns (KernelStrategy _vault) {
        KernelStrategy implementation = new KernelStrategy();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(ADMIN), "");

        uint8 decimals = 8;
        uint64 baseWithdrawalFee = 0;
        bool countNativeAssets = false;
        bool alwaysComputeTotalAssets = true;

        _vault = KernelStrategy(payable(address(proxy)));
        _vault.initialize(
            ADMIN,
            "YieldNest Restaked BitFi BTC - Kernel",
            "ynBfBTCk",
            decimals,
            baseWithdrawalFee,
            countNativeAssets,
            alwaysComputeTotalAssets
        );

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

        // all are set to false by default
        // vault_.setSyncDeposit(false);
        // vault_.setSyncWithdraw(false);
        // vault_.setHasAllocator(false);

        vault_.addAssetWithDecimals(MC.BFBTC, 8, true, true);

        // VERY IMPORTANT: BFBTC has 8 decimals
        // NOTE: we don't add the kernel vault here yet since bfBTC is not supported yet on kernel
        // vault_.addAssetWithDecimals(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.BFBTC), 8, false);

        // NOTE: we don't set any rules here yet since bfBTC is not supported yet on kernel
        // setApprovalRule(vault_, MC.BFBTC, MC.STAKER_GATEWAY);
        // setStakingRule(vault_, MC.STAKER_GATEWAY, MC.BFBTC);
        // setUnstakingRule(vault_, MC.STAKER_GATEWAY, MC.BFBTC);

        vault_.unpause();

        vm.stopPrank();
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
    }

    function test_Vault_ERC20_view_functions() public view {
        // Test the name function
        assertEq(
            vault.name(),
            "YieldNest Restaked BitFi BTC - Kernel",
            "Vault name should be 'YieldNest Restaked BitFi BTC - Kernel'"
        );

        // Test the symbol function
        assertEq(vault.symbol(), "ynBfBTCk", "Vault symbol should be 'ynBfBTCk'");

        // Test the decimals function
        assertEq(vault.decimals(), 8, "Vault decimals should be 8");

        // Test the totalSupply function
        vault.totalSupply();
    }

    function test_Vault_ERC4626_view_functions() public view {
        // Test the paused function
        assertFalse(vault.paused(), "Vault should not be paused");

        // Test the asset function
        assertEq(address(vault.asset()), MC.BFBTC, "Vault asset should be BFBTC");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        assertGe(totalAssets, totalSupply, "TotalAssets should be greater than totalSupply");

        uint256 amount = 1 ether;
        {
            // Test the convertToShares function
            uint256 shares = vault.convertToShares(amount);

            assertEq(shares, amount, "Shares for amount should be as expected");

            // Test the convertToAssets function
            uint256 convertedAssets = vault.convertToAssets(shares);
            assertApproxEqAbs(convertedAssets, amount, 2, "Converted assets should be equal to amount deposited");
        }

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
        assertEq(assets.length, 1, "There should be only 1 asset in the vault");
        assertEq(assets[0], MC.BFBTC, "First asset should be BFBTC");

        // Test the getAsset function for BFBTC
        assertEq(vault.getAsset(MC.BFBTC).decimals, 8, "Asset decimals should be 8");
        assertEq(vault.getAsset(MC.BFBTC).active, true, "Asset should be active");
        assertEq(vault.getAsset(MC.BFBTC).index, 0, "Asset index should be 0");

        {
            uint256 shares = vault.previewWithdrawAsset(MC.BFBTC, amount);
            uint256 convertedAssets = vault.previewRedeemAsset(MC.BFBTC, shares);

            assertEq(convertedAssets, amount, "Converted assets should be equal to amount");
        }
    }

    function test_Vault_ynBfBTCk_view_functions() public view {
        bool syncDeposit = vault.getSyncDeposit();
        assertFalse(syncDeposit, "SyncDeposit should be false");

        bool syncWithdraw = vault.getSyncWithdraw();
        assertFalse(syncWithdraw, "SyncWithdraw should be false");

        bool hasAllocator = vault.getHasAllocator();
        assertFalse(hasAllocator, "HasAllocator should be false");

        address strategyGateway = vault.getStakerGateway();
        assertEq(strategyGateway, MC.STAKER_GATEWAY, "incorrect staker gateway");
    }

    function depositIntoVault(address assetAddress, uint256 amount) internal returns (uint256) {
        IERC20 asset = IERC20(assetAddress);

        uint256 beforeTotalAssets = vault.totalAssets();
        uint256 beforeTotalShares = vault.totalSupply();
        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
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

        uint256 assetsInBase = vault.convertToAssets(shares);

        assertEq(
            vault.totalAssets(),
            beforeTotalAssets + assetsInBase,
            "Total assets should increase by the amount deposited"
        );
        assertEq(
            vault.totalSupply(), beforeTotalShares + shares, "Total shares should increase by the amount deposited"
        );

        assertEq(
            asset.balanceOf(address(vault)), beforeVaultBalance + amount, "Vault should have the asset after deposit"
        );
        assertEq(asset.balanceOf(bob), beforeBobBalance - amount, "Bob should not have the assets");
        assertEq(vault.balanceOf(bob), beforeBobShares + shares, "Bob should have shares after deposit");
        assertApproxEqAbs(
            viewer.maxWithdrawAsset(address(asset), bob),
            beforeMaxWithdraw + amount,
            2,
            "Bob should have max withdraw after deposit"
        );

        return shares;
    }

    function obtainBFBTC(address to, uint256 amount) internal returns (uint256) {
        deal(MC.BTCB, to, amount);

        uint256 beforeBalance = bfbtc.balanceOf(to);

        uint256 previewedAmount = bfbtc.previewDeposit(amount);
        uint256 minAmount = previewedAmount - 1;

        vm.startPrank(to);
        IERC20(MC.BTCB).approve(MC.BFBTC, amount);
        bfbtc.deposit(amount, minAmount);
        vm.stopPrank();

        uint256 afterBalance = bfbtc.balanceOf(to);

        return afterBalance - beforeBalance;
    }

    function test_Vault_ynBfBTCk_deposit_BFBTC(uint256 amount) public {
        amount = bound(amount, bfbtcMinDepositAmount, 100_000 ether);
        amount = obtainBFBTC(bob, amount);

        uint256 shares = depositIntoVault(MC.BFBTC, amount);

        uint256 convertedAssets = vault.convertToAssets(shares);
        assertApproxEqAbs(convertedAssets, amount, 2, "Assets in base should be equal to amount");
        assertApproxEqAbs(shares, amount, 2, "Shares should be equal to amount");
    }

    function test_Vault_ynBfBTCk_donate_BFBTC(uint256 amount) public {
        amount = bound(amount, bfbtcMinDepositAmount, 100_000 ether);
        amount = obtainBFBTC(bob, amount);

        IERC20 asset = IERC20(MC.BFBTC);

        uint256 beforeTotalAssets = vault.totalAssets();
        uint256 beforeTotalShares = vault.totalSupply();
        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);
        uint256 beforeMaxWithdraw = viewer.maxWithdrawAsset(address(asset), bob);
        assertEq(beforeMaxWithdraw, 0, "Bob should have no max withdraw before deposit");

        vm.prank(bob);
        asset.transfer(address(vault), amount);

        assertEq(
            vault.totalAssets(), beforeTotalAssets + amount, "Total assets should increase by the amount deposited"
        );
        assertEq(vault.totalSupply(), beforeTotalShares, "Total shares should remain the same after donation");

        assertEq(
            asset.balanceOf(address(vault)), beforeVaultBalance + amount, "Vault should have the asset after donation"
        );
        assertEq(asset.balanceOf(bob), beforeBobBalance - amount, "Bob should not have the assets");
        assertEq(vault.balanceOf(bob), beforeBobShares, "Bob should have same shares after donation");
        assertEq(
            viewer.maxWithdrawAsset(address(asset), bob),
            beforeMaxWithdraw,
            "Bob should have same max withdraw after donation"
        );
    }

    function test_Vault_ynBfBTCk_withdraw_BFBTC(uint256 amount) public {
        amount = bound(amount, bfbtcMinDepositAmount, 100_000 ether);
        amount = obtainBFBTC(bob, amount);

        depositIntoVault(MC.BFBTC, amount);
        IERC20 asset = IERC20(MC.BFBTC);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.BFBTC, bob);
        assertApproxEqAbs(maxWithdraw, amount, 2, "Max withdraw should be equal to amount");

        uint256 previewShares = vault.previewWithdrawAsset(MC.BFBTC, maxWithdraw);

        vm.prank(bob);
        uint256 shares = vault.withdrawAsset(MC.BFBTC, maxWithdraw, bob, bob);

        assertEq(shares, previewShares, "Shares should be equal to preview shares");

        uint256 afterVaultBalance = asset.balanceOf(address(vault));
        uint256 afterBobBalance = asset.balanceOf(bob);
        uint256 afterBobShares = vault.balanceOf(bob);

        assertEq(afterVaultBalance, beforeVaultBalance - maxWithdraw, "Vault balance should decrease be 0");
        assertEq(afterBobBalance, beforeBobBalance + maxWithdraw, "Bob balance should increase by maxWithdraw");
        assertEq(afterBobShares, beforeBobShares - shares, "Bob shares should decrease by shares");
    }

    function test_Vault_ynBfBTCk_redeem_BFBTC(uint256 amount) public {
        amount = bound(amount, bfbtcMinDepositAmount, 100_000 ether);
        amount = obtainBFBTC(bob, amount);

        IERC20 asset = IERC20(MC.BFBTC);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 shares = depositIntoVault(MC.BFBTC, amount);

        uint256 previewAssets = vault.previewRedeemAsset(MC.BFBTC, shares);

        vm.prank(bob);
        uint256 assets = vault.redeemAsset(MC.BFBTC, shares, bob, bob);

        assertEq(previewAssets, assets, "Preview assets should be equal to assets");

        assertApproxEqAbs(assets, amount, 2, "Assets should be equal to amount");

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

    function test_Vault_ynBfBTCk_rewards_BFBTC(uint256 amount, uint256 rewards) public {
        amount = bound(amount, bfbtcMinDepositAmount, 100_000 ether);
        rewards = bound(rewards, bfbtcMinDepositAmount, amount);
        amount = obtainBFBTC(bob, amount);
        rewards = obtainBFBTC(bob, rewards);

        assertGe(bfbtc.balanceOf(bob), rewards + amount, "Bob should have enough rewards & amount");

        depositIntoVault(MC.BFBTC, amount);

        uint256 rewardsForBob = rewards * vault.balanceOf(bob) / vault.totalSupply();

        {
            uint256 beforeAssets = vault.totalAssets();
            uint256 beforeShares = vault.totalSupply();
            uint256 beforeMaxWithdraw = viewer.maxWithdrawAsset(address(MC.BFBTC), bob);
            uint256 beforeBobShares = vault.balanceOf(bob);

            vm.prank(bob);
            bfbtc.transfer(address(vault), rewards);

            uint256 afterMaxWithdraw = viewer.maxWithdrawAsset(address(MC.BFBTC), bob);

            assertApproxEqAbs(vault.totalAssets(), beforeAssets + rewards, 2, "Total assets should increase by rewards");
            assertEq(vault.totalSupply(), beforeShares, "Total shares should not change");
            assertApproxEqAbs(
                afterMaxWithdraw, beforeMaxWithdraw + rewardsForBob, 2, "Max withdraw should increase by rewards"
            );
            assertEq(vault.balanceOf(bob), beforeBobShares, "Bob should have same shares");
        }

        {
            IERC20 asset = IERC20(MC.BFBTC);

            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeBobBalance = asset.balanceOf(bob);
            uint256 beforeBobShares = vault.balanceOf(bob);

            uint256 maxWithdraw = vault.maxWithdrawAsset(MC.BFBTC, bob);
            assertApproxEqAbs(
                maxWithdraw, amount + rewardsForBob, 2, "Max withdraw should be equal to amount + rewards"
            );

            uint256 previewShares = vault.previewWithdrawAsset(MC.BFBTC, maxWithdraw);

            vm.prank(bob);
            uint256 shares = vault.withdrawAsset(MC.BFBTC, maxWithdraw, bob, bob);

            assertEq(shares, previewShares, "Shares should be equal to preview shares");

            uint256 afterVaultBalance = asset.balanceOf(address(vault));
            uint256 afterBobBalance = asset.balanceOf(bob);
            uint256 afterBobShares = vault.balanceOf(bob);

            assertEq(afterBobBalance, beforeBobBalance + maxWithdraw, "Bob balance should increase by maxWithdraw");
            assertEq(afterBobShares, beforeBobShares - shares, "Bob shares should decrease by shares");
            assertEq(vault.maxWithdrawAsset(MC.BFBTC, bob), 0, "Max withdraw should be zero");

            assertEq(afterVaultBalance, beforeVaultBalance - maxWithdraw, "Vault balance should decrease");
        }
    }

    function test_Vault_ynBfBTCk_deposit_BFBTC_WithKernelVault(uint256 amount) public {
        amount = bound(amount, bfbtcMinDepositAmount, 100_000 ether);
        amount = obtainBFBTC(bob, amount);

        IKernelVault kernelVault = _deployKernelVaultAndAddToAssetRegistry(MC.BFBTC);
        _configureKernelStrategyToSupportKernelVault(vault, kernelVault);

        uint256 shares = _depositIntoVault_WithKernelVault(MC.BFBTC, amount);

        uint256 convertedAssets = vault.convertToAssets(shares);
        assertApproxEqAbs(convertedAssets, amount, 2, "Assets in base should be equal to amount");
        assertApproxEqAbs(shares, amount, 2, "Shares should be equal to amount");
    }

    function test_Vault_ynBfBTCk_donate_BFBTC_WithKernelVault(uint256 amount) public {
        amount = bound(amount, bfbtcMinDepositAmount, 100_000 ether);
        amount = obtainBFBTC(bob, amount);

        IKernelVault kernelVault = _deployKernelVaultAndAddToAssetRegistry(MC.BFBTC);
        _configureKernelStrategyToSupportKernelVault(vault, kernelVault);

        IERC20 asset = IERC20(MC.BFBTC);

        uint256 beforeTotalAssets = vault.totalAssets();
        uint256 beforeTotalShares = vault.totalSupply();
        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeKernelVaultBalance = asset.balanceOf(address(kernelVault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);
        uint256 beforeMaxWithdraw = viewer.maxWithdrawAsset(address(asset), bob);
        assertEq(beforeMaxWithdraw, 0, "Bob should have no max withdraw before deposit");

        vm.prank(bob);
        asset.transfer(address(vault), amount);

        assertEq(
            vault.totalAssets(), beforeTotalAssets + amount, "Total assets should increase by the amount deposited"
        );
        assertEq(vault.totalSupply(), beforeTotalShares, "Total shares should remain the same after donation");

        assertEq(
            asset.balanceOf(address(vault)), beforeVaultBalance + amount, "Vault should have the asset after donation"
        );
        assertEq(asset.balanceOf(bob), beforeBobBalance - amount, "Bob should not have the assets");
        assertEq(vault.balanceOf(bob), beforeBobShares, "Bob should have same shares after donation");
        assertEq(
            viewer.maxWithdrawAsset(address(asset), bob),
            beforeMaxWithdraw,
            "Bob should have same max withdraw after donation"
        );
        assertEq(asset.balanceOf(address(kernelVault)), beforeKernelVaultBalance, "Kernel vault should not have assets");
    }

    function test_Vault_ynBfBTCk_withdraw_BFBTC_WithKernelVault(uint256 amount) public {
        amount = bound(amount, bfbtcMinDepositAmount, 100_000 ether);
        amount = obtainBFBTC(bob, amount);

        IKernelVault kernelVault = _deployKernelVaultAndAddToAssetRegistry(MC.BFBTC);
        _configureKernelStrategyToSupportKernelVault(vault, kernelVault);

        _depositIntoVault_WithKernelVault(MC.BFBTC, amount);

        IERC20 asset = IERC20(MC.BFBTC);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);
        uint256 beforeVaultStakerShares = stakerGateway.balanceOf(address(asset), address(vault));

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.BFBTC, bob);
        assertApproxEqAbs(maxWithdraw, amount, 2, "Max withdraw should be equal to amount");

        uint256 previewShares = vault.previewWithdrawAsset(MC.BFBTC, maxWithdraw);

        vm.prank(bob);
        uint256 shares = vault.withdrawAsset(MC.BFBTC, maxWithdraw, bob, bob);

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

    function test_Vault_ynBfBTCk_redeem_BFBTC_WithKernelVault(uint256 amount) public {
        amount = bound(amount, bfbtcMinDepositAmount, 100_000 ether);
        amount = obtainBFBTC(bob, amount);

        IKernelVault kernelVault = _deployKernelVaultAndAddToAssetRegistry(MC.BFBTC);
        _configureKernelStrategyToSupportKernelVault(vault, kernelVault);

        IERC20 asset = IERC20(MC.BFBTC);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 shares = _depositIntoVault_WithKernelVault(MC.BFBTC, amount);

        uint256 previewAssets = vault.previewRedeemAsset(MC.BFBTC, shares);

        assertGe(asset.balanceOf(address(kernelVault)), previewAssets, "Vault should have enough assets to withdraw");

        vm.prank(bob);
        uint256 assets = vault.redeemAsset(MC.BFBTC, shares, bob, bob);

        assertEq(previewAssets, assets, "Preview assets should be equal to assets");

        assertApproxEqAbs(assets, amount, 2, "Assets should be equal to amount");

        assertApproxEqAbs(
            asset.balanceOf(address(vault)),
            beforeVaultBalance + amount - assets,
            2,
            "Vault should have transferred the asset to bob"
        );
        assertApproxEqAbs(
            asset.balanceOf(bob),
            beforeBobBalance - amount + assets,
            2,
            "Bob should have the amount deposited after withdraw"
        );
        assertEq(vault.balanceOf(bob), beforeBobShares, "Bob should have no shares after withdraw");
    }

    function test_Vault_ynBfBTCk_rewards_BFBTC_WithKernelVault(uint256 amount, uint256 rewards) public {
        amount = bound(amount, bfbtcMinDepositAmount, 100_000 ether);
        rewards = bound(rewards, bfbtcMinDepositAmount, amount);
        amount = obtainBFBTC(bob, amount);
        rewards = obtainBFBTC(bob, rewards);

        assertGe(bfbtc.balanceOf(bob), rewards + amount, "Bob should have enough rewards & amount");

        IKernelVault kernelVault = _deployKernelVaultAndAddToAssetRegistry(MC.BFBTC);
        _configureKernelStrategyToSupportKernelVault(vault, kernelVault);

        _depositIntoVault_WithKernelVault(MC.BFBTC, amount);

        uint256 rewardsForBob = rewards * vault.balanceOf(bob) / vault.totalSupply();

        IERC20 asset = IERC20(MC.BFBTC);

        {
            uint256 beforeAssets = vault.totalAssets();
            uint256 beforeShares = vault.totalSupply();
            uint256 beforeMaxWithdraw = viewer.maxWithdrawAsset(address(MC.BFBTC), bob);
            uint256 beforeBobShares = vault.balanceOf(bob);
            uint256 beforeKernelVaultBalance = bfbtc.balanceOf(address(kernelVault));
            uint256 beforeVaultBalance = bfbtc.balanceOf(address(vault));

            vm.prank(bob);
            bfbtc.transfer(address(vault), rewards);

            uint256 afterMaxWithdraw = viewer.maxWithdrawAsset(address(MC.BFBTC), bob);
            assertApproxEqAbs(vault.totalAssets(), beforeAssets + rewards, 2, "Total assets should increase by rewards");
            assertEq(vault.totalSupply(), beforeShares, "Total shares should not change");
            assertApproxEqAbs(
                afterMaxWithdraw, beforeMaxWithdraw + rewardsForBob, 2, "Max withdraw should increase by rewards"
            );
            assertEq(vault.balanceOf(bob), beforeBobShares, "Bob should have same shares");
            assertEq(
                asset.balanceOf(address(kernelVault)), beforeKernelVaultBalance, "Kernel vault should not have assets"
            );
            assertEq(asset.balanceOf(address(vault)), beforeVaultBalance + rewards, "Vault should have rewards");
        }

        {
            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeKernelVaultBalance = asset.balanceOf(address(kernelVault));
            uint256 beforeBobBalance = asset.balanceOf(bob);
            uint256 beforeBobShares = vault.balanceOf(bob);

            uint256 maxWithdraw = vault.maxWithdrawAsset(MC.BFBTC, bob);
            assertApproxEqAbs(
                maxWithdraw, amount + rewardsForBob, 2, "Max withdraw should be equal to amount + rewards"
            );

            uint256 previewShares = vault.previewWithdrawAsset(MC.BFBTC, maxWithdraw);

            vm.prank(bob);
            uint256 shares = vault.withdrawAsset(MC.BFBTC, maxWithdraw, bob, bob);

            assertEq(shares, previewShares, "Shares should be equal to preview shares");

            uint256 afterVaultBalance = asset.balanceOf(address(vault));
            uint256 afterBobBalance = asset.balanceOf(bob);
            uint256 afterBobShares = vault.balanceOf(bob);

            assertEq(afterBobBalance, beforeBobBalance + maxWithdraw, "Bob balance should increase by maxWithdraw");
            assertEq(afterBobShares, beforeBobShares - shares, "Bob shares should decrease by shares");
            assertEq(vault.maxWithdrawAsset(MC.BFBTC, bob), 0, "Max withdraw should be zero");

            if (beforeVaultBalance > maxWithdraw) {
                assertEq(afterVaultBalance, beforeVaultBalance - maxWithdraw, "Vault balance should decrease");
                assertEq(
                    asset.balanceOf(address(kernelVault)),
                    beforeKernelVaultBalance,
                    "Kernel vault balance should not change"
                );
            } else {
                assertEq(afterVaultBalance, 0, "Vault balance should not decrease");
                assertEq(
                    asset.balanceOf(address(kernelVault)),
                    beforeKernelVaultBalance + beforeVaultBalance - maxWithdraw,
                    "Kernel vault should only change by withdrawn amount"
                );
            }
        }
    }

    function _depositIntoVault_WithKernelVault(address assetAddress, uint256 amount) internal returns (uint256) {
        IERC20 asset = IERC20(assetAddress);

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(assetAddress);

        uint256 beforeTotalAssets = vault.totalAssets();
        uint256 beforeTotalShares = vault.totalSupply();
        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeKernelVaultBalance = asset.balanceOf(address(kernelVault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 previewShares = vault.previewDepositAsset(assetAddress, amount);

        vm.prank(bob);
        asset.approve(address(vault), amount);

        // Test the deposit function
        vm.prank(bob);
        uint256 shares = vault.depositAsset(assetAddress, amount, bob);

        assertEq(previewShares, shares, "Preview shares should be equal to shares");

        uint256 assetsInBase = vault.convertToAssets(shares);

        assertEq(
            vault.totalAssets(),
            beforeTotalAssets + assetsInBase,
            "Total assets should increase by the amount deposited"
        );
        assertEq(
            vault.totalSupply(), beforeTotalShares + shares, "Total shares should increase by the amount deposited"
        );

        assertEq(asset.balanceOf(address(vault)), beforeVaultBalance, "Vault balance should not change");
        assertEq(
            asset.balanceOf(address(kernelVault)),
            beforeKernelVaultBalance + amount,
            "Vault should have the asset after deposit"
        );
        assertEq(asset.balanceOf(bob), beforeBobBalance - amount, "Bob should not have the assets");
        assertEq(vault.balanceOf(bob), beforeBobShares + shares, "Bob should have shares after deposit");

        return shares;
    }

    function _configureKernelStrategyToSupportKernelVault(KernelStrategy vault_, IKernelVault kernelVault) internal {
        vm.startPrank(ADMIN);

        // syncDeposit and syncWithdraw are set to true
        vault_.setSyncDeposit(true);
        vault_.setSyncWithdraw(true);

        // add kernel vault as an asset
        vault_.addAssetWithDecimals(address(kernelVault), 8, false);

        // set rules for kernel vault
        setApprovalRule(vault_, MC.BFBTC, MC.STAKER_GATEWAY);
        setStakingRule(vault_, MC.STAKER_GATEWAY, MC.BFBTC);
        setUnstakingRule(vault_, MC.STAKER_GATEWAY, MC.BFBTC);

        vm.stopPrank();
    }

    function _deployKernelVaultAndAddToAssetRegistry(address asset) internal returns (IKernelVault) {
        // initialize
        bytes memory initializeData = abi.encodeCall(IKernelVault.initialize, (address(asset), address(kernelConfig)));

        BeaconProxy proxy = new BeaconProxy(address(MC.KERNEL_VAULT_BEACON), initializeData);

        // deploy Vault
        IKernelVault kernelVault = IKernelVault(address(proxy));

        address alice = address(0xA11CE);

        vm.startPrank(MC.KERNEL_CONFIG_ADMIN);
        // add asset to AssetRegistry
        assetRegistry.addAsset(address(kernelVault));
        // grant manager role to this contract for setting deposit limit
        kernelConfig.grantRole(kernelConfig.ROLE_MANAGER(), address(alice));
        vm.stopPrank();

        vm.startPrank(alice);
        // set deposit limit to max
        kernelVault.setDepositLimit(type(uint256).max);
        // renounce manager role
        kernelConfig.renounceRole(kernelConfig.ROLE_MANAGER(), address(alice));
        vm.stopPrank();

        assertEq(stakerGateway.getVault(asset), address(kernelVault), "Staker gateway should have kernel vault");

        // return kernel vault
        return kernelVault;
    }
}
