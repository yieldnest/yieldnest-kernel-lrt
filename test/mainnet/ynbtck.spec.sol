// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";

import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";

import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {BaseVaultViewer, KernelVaultViewer} from "src/utils/KernelVaultViewer.sol";

import {VaultUtils} from "script/VaultUtils.sol";
import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {BTCRateProvider} from "src/module/BTCRateProvider.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";

contract YnBTCkTest is Test, AssertUtils, MainnetActors, EtchUtils, VaultUtils {
    KernelStrategy public vault;
    BTCRateProvider public kernelProvider;
    IStakerGateway public stakerGateway;
    KernelVaultViewer public viewer;

    address public bob = address(0xB0B);

    WETH9 public btcb;

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

        etchBTCB();
        mockDepositLimit();
    }

    function etchBTCB() public {
        WETH9 mock = new WETH9();
        vm.etch(MC.BTCB, address(mock).code);
        btcb = WETH9(payable(MC.BTCB));
    }

    function mockDepositLimit() public {
        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.BTCB);
        address config = IKernelVault(kernelVault).getConfig();
        bytes32 role = IKernelConfig(config).ROLE_MANAGER();

        vm.prank(MC.KERNEL_CONFIG_ADMIN);
        IKernelConfig(config).grantRole(role, address(this));

        IKernelVault(kernelVault).setDepositLimit(type(uint256).max);

        assertEq(IKernelVault(kernelVault).getDepositLimit(), type(uint256).max, "Deposit limit should be max");
    }

    function deploy() public returns (KernelStrategy _vault) {
        KernelStrategy implementation = new KernelStrategy();
        bytes memory initData = abi.encodeWithSelector(
            KernelStrategy.initialize.selector, ADMIN, "YieldNest Restaked BTC - Kernel", "ynBTCk", 18, 0, false
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(MainnetActors.ADMIN), initData);

        _vault = KernelStrategy(payable(address(proxy)));

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

        vault_.addAsset(MC.BTCB, true);
        vault_.addAsset(MC.SOLVBTC, true);
        vault_.addAsset(MC.SOLVBTC_BNN, true);

        vault_.addAssetWithDecimals(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.BTCB), 18, false);
        vault_.addAssetWithDecimals(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SOLVBTC), 18, false);
        vault_.addAssetWithDecimals(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SOLVBTC_BNN), 18, false);

        // set deposit rules
        setApprovalRule(vault_, MC.BTCB, MC.STAKER_GATEWAY);
        setStakingRule(vault_, MC.STAKER_GATEWAY, MC.BTCB);

        setApprovalRule(vault_, MC.SOLVBTC, MC.STAKER_GATEWAY);
        setStakingRule(vault_, MC.STAKER_GATEWAY, MC.SOLVBTC);

        setApprovalRule(vault_, MC.SOLVBTC_BNN, MC.STAKER_GATEWAY);
        setStakingRule(vault_, MC.STAKER_GATEWAY, MC.SOLVBTC_BNN);

        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
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

        vault.processAccounting();
    }

    function test_Vault_Upgrade_ERC20_view_functions() public view {
        // Test the name function
        assertEq(
            vault.name(), "YieldNest Restaked BTC - Kernel", "Vault name should be 'YieldNest Restaked BTC - Kernel'"
        );

        // Test the symbol function
        assertEq(vault.symbol(), "ynBTCk", "Vault symbol should be 'ynBTCk'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        vault.totalSupply();
    }

    function test_Vault_Upgrade_ERC4626_view_functions() public view {
        // Test the paused function
        assertFalse(vault.paused(), "Vault should not be paused");

        // Test the asset function
        assertEq(address(vault.asset()), MC.BTCB, "Vault asset should be BTCB");

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
        assertEq(assets[0], MC.BTCB, "First asset should be BTCB");
        assertEq(assets[1], MC.SOLVBTC, "Second asset should be SOLVBTC");
        assertEq(assets[2], MC.SOLVBTC_BNN, "Third asset should be SOLVBTC_BNN");

        shares = vault.previewWithdrawAsset(MC.BTCB, amount);
        convertedAssets = vault.previewRedeemAsset(MC.BTCB, shares);

        assertEqThreshold(convertedAssets, amount, 10, "Converted assets should be equal to amount");
    }

    function test_Vault_ynBTCk_view_functions() public view {
        bool syncDeposit = vault.getSyncDeposit();
        assertTrue(syncDeposit, "SyncDeposit should be true");

        bool syncWithdraw = vault.getSyncWithdraw();
        assertTrue(syncWithdraw, "SyncWithdraw should be true");

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

        vault.processAccounting();

        assertEq(previewShares, shares, "Preview shares should be equal to shares");

        uint256 assetsInBTC = vault.convertToAssets(shares);

        assertEqThreshold(
            vault.totalAssets(),
            beforeTotalAssets + assetsInBTC,
            10,
            "Total assets should increase by the amount deposited"
        );
        assertEq(
            vault.totalSupply(), beforeTotalShares + shares, "Total shares should increase by the amount deposited"
        );
        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.BTCB);
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

    function getBTCB(uint256 amount) internal {
        vm.deal(bob, amount);

        vm.prank(bob);
        btcb.deposit{value: amount}();

        assertGe(btcb.balanceOf(bob), amount, "Should have tokens");
    }

    function test_Vault_ynBTCk_deposit_BTCB(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);

        IERC20 asset = IERC20(MC.BTCB);

        //set sync deposit enabled
        vm.prank(ADMIN);
        vault.setSyncDeposit(true);

        uint256 beforeVaultBalance = stakerGateway.balanceOf(address(asset), address(vault));
        uint256 previewShares = vault.previewDepositAsset(address(asset), amount);

        getBTCB(amount);

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

    function test_Vault_ynBTCk_withdraw_BTCB(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);

        getBTCB(amount);

        depositIntoVault(MC.BTCB, amount);
        IERC20 asset = IERC20(MC.BTCB);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);
        uint256 beforeVaultStakerShares = stakerGateway.balanceOf(address(asset), address(vault));

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.BTCB, bob);
        assertEqThreshold(maxWithdraw, amount, 2, "Max withdraw should be equal to amount");

        uint256 previewShares = vault.previewWithdrawAsset(MC.BTCB, maxWithdraw);

        vm.prank(bob);
        uint256 shares = vault.withdrawAsset(MC.BTCB, maxWithdraw, bob, bob);

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

    function test_Vault_ynBTCk_redeem_BTCB(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);

        getBTCB(amount);

        IERC20 asset = IERC20(MC.BTCB);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 shares = depositIntoVault(MC.BTCB, amount);

        uint256 previewAssets = vault.previewRedeemAsset(MC.BTCB, shares);

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.BTCB);
        assertGe(asset.balanceOf(address(kernelVault)), previewAssets, "Vault should have enough assets to withdraw");

        vm.prank(bob);
        uint256 assets = vault.redeemAsset(MC.BTCB, shares, bob, bob);

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

    function test_Vault_ynBTCk_rewards_BTCB(uint256 amount, uint256 rewards) public {
        amount = bound(amount, 1000, 100_000 ether);
        rewards = bound(rewards, 10, amount / 10);

        getBTCB(amount);

        depositIntoVault(MC.BTCB, amount);

        uint256 rewardsForBob = rewards * vault.balanceOf(bob) / vault.totalSupply();

        {
            uint256 beforeAssets = vault.totalAssets();
            uint256 beforeShares = vault.totalSupply();
            uint256 beforeMaxWithdraw = viewer.maxWithdrawAsset(address(MC.BTCB), bob);
            uint256 beforeBobShares = vault.balanceOf(bob);

            getBTCB(rewards);

            vm.prank(bob);
            btcb.transfer(address(vault), rewards);

            vault.processAccounting();

            uint256 afterAssets = vault.totalAssets();
            uint256 afterMaxWithdraw = viewer.maxWithdrawAsset(address(MC.BTCB), bob);

            assertEq(afterAssets, beforeAssets + rewards, "Total assets should increase by rewards");
            assertEq(vault.totalSupply(), beforeShares, "Total shares should not change");
            assertEqThreshold(
                afterMaxWithdraw, beforeMaxWithdraw + rewardsForBob, 10, "Max withdraw should increase by rewards"
            );
            assertEq(vault.balanceOf(bob), beforeBobShares, "Bob should have same shares");
        }

        {
            IERC20 asset = IERC20(MC.BTCB);

            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeBobBalance = asset.balanceOf(bob);
            uint256 beforeBobShares = vault.balanceOf(bob);
            uint256 beforeVaultStakerShares = stakerGateway.balanceOf(address(asset), address(vault));

            uint256 maxWithdraw = vault.maxWithdrawAsset(MC.BTCB, bob);
            assertEqThreshold(maxWithdraw, amount + rewardsForBob, 10, "Max withdraw should be equal to amount");

            uint256 previewShares = vault.previewWithdrawAsset(MC.BTCB, maxWithdraw);

            vm.prank(bob);
            uint256 shares = vault.withdrawAsset(MC.BTCB, maxWithdraw, bob, bob);

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
