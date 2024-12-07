// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";

import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";

import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {KernelClisStrategy} from "src/KernelClisStrategy.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";

import {VaultUtils} from "script/VaultUtils.sol";
import {IWBNB} from "src/interface/external/IWBNB.sol";
import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {BNBRateProvider} from "src/module/BNBRateProvider.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";
import {IAccessControl} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";


contract YnClisBNBkTest is Test, AssertUtils, MainnetActors, EtchUtils, VaultUtils {
    KernelClisStrategy public vault;
    BNBRateProvider public kernelProvider;
    IStakerGateway public stakerGateway;

    address public bob = address(0xB0B);
    address public clisBnbVault;

    function setUp() public {
        kernelProvider = new BNBRateProvider();
        etchProvider(address(kernelProvider));

        stakerGateway = IStakerGateway(MC.STAKER_GATEWAY);

        clisBnbVault = IKernelConfig(stakerGateway.getConfig()).getClisBnbAddress();

        vault = deployClisBNBk();

        vm.label(MC.STAKER_GATEWAY, "kernel staker gateway");
        vm.label(address(vault), "kernel strategy");
        vm.label(address(kernelProvider), "kernel rate provider");
    }

    function deployClisBNBk() public returns (KernelClisStrategy _vault) {
        KernelClisStrategy implementation = new KernelClisStrategy();
        bytes memory initData = abi.encodeWithSelector(
            KernelClisStrategy.initialize.selector,
            MainnetActors.ADMIN,
            "YieldNest Restaked slisBNB - Kernel",
            "ynclisWBNBk",
            18,
            0,
            true
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(MainnetActors.ADMIN), initData);

        _vault = KernelClisStrategy(payable(address(proxy)));

        configureKernelClisStrategy(_vault);
    }

    function configureKernelClisStrategy(KernelClisStrategy vault_) public {

        vm.startPrank(ADMIN);

        vault_.grantRole(vault_.PROCESSOR_ROLE(), PROCESSOR);
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault_.grantRole(vault_.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault_.grantRole(vault_.PAUSER_ROLE(), PAUSER);
        vault_.grantRole(vault_.UNPAUSER_ROLE(), UNPAUSER);

        vault_.setHasAllocator(true);

        // since we're not testing the max vault, we'll set the admin as the allocator role
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), address(bob));

        // set strategy manager to admin for now
        vault_.grantRole(vault_.STRATEGY_MANAGER_ROLE(), address(ADMIN));

        vault_.setProvider(address(kernelProvider));

        vault_.setStakerGateway(MC.STAKER_GATEWAY);

        vault_.setSyncDeposit(true);

        vault_.addAsset(MC.WBNB, true);
        vault_.addAssetWithDecimals(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.CLISBNB), 18, false);

        // set deposit rules
        setDepositRule(KernelStrategy(payable(address(vault_))), MC.WBNB, address(vault_));

        // set approval rules
        setApprovalRule(KernelStrategy(payable(address(vault_))), address(vault_), MC.STAKER_GATEWAY);

        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
    }

    function stakeIntoKernel(uint256 amount) public {
        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SLISBNB);
        address config = IKernelVault(kernelVault).getConfig();
        bytes32 role = IKernelConfig(config).ROLE_MANAGER();

        vm.prank(MC.KERNEL_CONFIG_ADMIN);
        IKernelConfig(config).grantRole(role, address(this));

        IKernelVault(kernelVault).setDepositLimit(type(uint256).max);

        address[] memory targets = new address[](1);

        targets[0] = MC.STAKER_GATEWAY;

        uint256[] memory values = new uint256[](1);
        values[0] = amount;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("stakeClisBNB(string)", "referral_id");

        vm.prank(ADMIN);
        vault.processor(targets, values, data);

        vault.processAccounting();
    }

    function test_Buffer_Vault_deposit_without_allocator() public {
        uint256 amount = 0.5 ether;
        
        address depositor = address(1241251261);
        // Give some WBNB
        giveWBNB(depositor, amount);

        vm.startPrank(depositor);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                depositor,
                vault.ALLOCATOR_ROLE()
            )
        );
        vault.depositAsset(MC.WBNB, amount, depositor);
    }

    function test_Buffer_Vault_withdraw_without_allocator() public {
        uint256 amount = 0.5 ether;
        
        address withdrawer = address(1241251261);
        // Give some shares
        giveWBNB(bob, amount);
        vm.startPrank(bob);
        IERC20(MC.WBNB).approve(address(vault), amount);
        vault.depositAsset(MC.WBNB, amount, withdrawer);
        vm.stopPrank();

        vm.startPrank(withdrawer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                withdrawer,
                vault.ALLOCATOR_ROLE()
            )
        );
        vault.withdrawAsset(MC.WBNB, amount, withdrawer, withdrawer);
        vm.stopPrank();
    }

    function depositIntoVault(address assetAddress, uint256 amount) internal returns (uint256) {
        IERC20 asset = IERC20(assetAddress);

        uint256 beforeTotalAssets = vault.totalAssets();
        uint256 beforeTotalShares = vault.totalSupply();
        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 previewShares = vault.previewDepositAsset(assetAddress, amount);

        vm.prank(bob);
        asset.approve(address(vault), amount);

        // Test the deposit function
        vm.prank(bob);
        uint256 shares = vault.depositAsset(assetAddress, amount, bob);

        vault.processAccounting();

        assertEq(previewShares, shares, "Preview shares should be equal to shares");

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
        assertEq(
            asset.balanceOf(address(vault)), beforeVaultBalance + amount, "Vault should have the asset after deposit"
        );
        assertEq(asset.balanceOf(bob), beforeBobBalance - amount, "Bob should not have the assets");
        assertEq(vault.balanceOf(bob), beforeBobShares + shares, "Bob should have shares after deposit");

        return shares;
    }

    function giveWBNB(address account, uint256 amount) public {
        vm.deal(account, amount);
        uint256 beforeBalance = IWBNB(MC.WBNB).balanceOf(account);
        vm.prank(account);
        IWBNB(MC.WBNB).deposit{value: amount}();

        assertEq(IWBNB(MC.WBNB).balanceOf(account), beforeBalance + amount, "wbnb not sent");
    }

    function test_ynclisBNBk_deposit_success_syncEnabled() public {
        uint256 amount = 1 ether;

        giveWBNB(bob, amount);

        vm.prank(ADMIN);
        vault.setSyncDeposit(true);

        IERC20 asset = IERC20(MC.WBNB);

        uint256 beforeTotalShares = vault.totalSupply();
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 previewShares = vault.previewDepositAsset(MC.WBNB, amount);

        vm.prank(bob);
        asset.approve(address(vault), amount);

        // Test the deposit function
        vm.prank(bob);
        uint256 shares = vault.depositAsset(MC.WBNB, amount, bob);

        vault.processAccounting();

        assertEq(previewShares, shares, "Preview shares should be equal to shares");

        assertEq(
            vault.totalSupply(), beforeTotalShares + shares, "Total shares should increase by the amount deposited"
        );
        assertEq(asset.balanceOf(bob), beforeBobBalance - amount, "Bob should not have the assets");
        assertEq(vault.balanceOf(bob), beforeBobShares + shares, "Bob should have shares after deposit");
        assertEq(
            stakerGateway.balanceOf(clisBnbVault, address(vault)), amount, "vault should have shares after deposit"
        );
    }

    function test_ynclisBNBk_wihtdraw_success_syncEnabled() public {
        uint256 amount = 1 ether;
        IERC20 asset = IERC20(MC.WBNB);
        giveWBNB(bob, amount);

        vm.startPrank(ADMIN);
        vault.setSyncDeposit(true);
        vault.setSyncWithdraw(true);
        vm.stopPrank();

        vm.prank(bob);
        asset.approve(address(vault), amount);

        vm.prank(bob);
        uint256 shares = vault.depositAsset(MC.WBNB, amount, bob);

        vault.processAccounting();

        uint256 maxWithdraw = vault.maxWithdraw(bob);
        uint256 vaultShares = stakerGateway.balanceOf(clisBnbVault, address(vault));
        assertGt(vaultShares, 0, "vault should have some shares");
        assertGt(maxWithdraw, 0, "max withdraw should not be 0");
        assertEq(maxWithdraw, shares, "incorrect maxWithdraw amount");

        assertEq(
            stakerGateway.balanceOf(clisBnbVault, address(vault)), amount, "vault should have shares after deposit"
        );

        uint256 withdrawAmount = vault.maxWithdraw(bob);
        assertGt(withdrawAmount, 0, "can't withdraw 0");

        uint256 beforeTotalShares = vault.totalSupply();
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        vm.prank(bob);
        vault.withdraw(withdrawAmount, bob, bob);
        vault.processAccounting();
        uint256 previewShares = vault.previewDepositAsset(MC.WBNB, amount);

        assertEq(previewShares, shares, "Preview shares should be equal to shares");

        assertEq(
            vault.totalSupply(), beforeTotalShares - shares, "Total shares should decrease by the amount withdrawn"
        );
        assertEq(asset.balanceOf(bob), beforeBobBalance + amount, "Bob should have the assets");
        assertEq(vault.balanceOf(bob), beforeBobShares - shares, "Bob should not have shares after withdraw");
        assertEq(stakerGateway.balanceOf(clisBnbVault, address(vault)), 0, "vault should have 0 shares after deposit");
    }
}
