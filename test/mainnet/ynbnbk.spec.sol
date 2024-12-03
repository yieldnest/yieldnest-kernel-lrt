// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";
import {SetupVault, Vault, IVault} from "lib/yieldnest-vault/test/mainnet/helpers/SetupVault.sol";
import {MigratedKernelStrategy} from "src/MigratedKernelStrategy.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";
import {KernelRateProvider} from "src/module/KernelRateProvider.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {MainnetActors} from "script/Actors.sol";
import {ProxyAdmin, IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {ISlisBnbStakeManager} from "lib/yieldnest-vault/src/interface/external/lista/ISlisBnbStakeManager.sol";

contract YnBNBkTest is Test, AssertUtils, MainnetActors, EtchUtils {
    KernelStrategy public vault;
    KernelStrategy public buffer;
    KernelRateProvider public kernelProvider;

    address bob = address(0xB0B);

    function setUp() public {
        kernelProvider = new KernelRateProvider();
        etchProvider(address(kernelProvider));

        vault = deployMigrateVault();
    }

    function deployMigrateVault() internal returns (KernelStrategy) {
        MigratedKernelStrategy migrationVault = MigratedKernelStrategy(payable(MC.YNBNBk));

        uint256 previousTotalAssets = migrationVault.totalAssets();

        uint256 previousTotalSupply = migrationVault.totalSupply();

        address specificHolder = 0xCfac0990700eD9B67FeFBD4b26a79E426468a419;

        uint256 previousBalance = migrationVault.balanceOf(specificHolder);

        MigratedKernelStrategy implemention = new MigratedKernelStrategy();

        ProxyAdmin proxyAdmin = ProxyAdmin(MC.YNBNBk_PROXY_ADMIN);

        vm.prank(proxyAdmin.owner());

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(MC.YNBNBk),
            address(implemention),
            abi.encodeWithSelector(
                KernelStrategy.initialize.selector,
                address(MainnetActors.ADMIN),
                "YieldNest Restaked BNB - Kernel",
                "ynBNBk",
                18
            )
        );

        MigratedKernelStrategy.Asset[] memory assets = new MigratedKernelStrategy.Asset[](3);

        assets[0] = MigratedKernelStrategy.Asset({asset: MC.WBNB, decimals: 18, active: false});
        assets[1] = MigratedKernelStrategy.Asset({asset: MC.SLISBNB, decimals: 18, active: true});
        assets[2] = MigratedKernelStrategy.Asset({asset: MC.BNBX, decimals: 18, active: true});

        vm.prank(proxyAdmin.owner());

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(MC.YNBNBk),
            address(implemention),
            abi.encodeWithSelector(
                MigratedKernelStrategy.initializeAndMigrate.selector,
                address(MainnetActors.ADMIN),
                "YieldNest Restaked BNB - Kernel",
                "ynBNBk",
                18,
                assets,
                MC.STAKER_GATEWAY,
                false,
                true
            )
        );

        vault = KernelStrategy(payable(address(migrationVault)));
        configureVault(vault);

        uint256 newTotalAssets = migrationVault.totalAssets();
        assertEqThreshold(
            newTotalAssets, previousTotalAssets, 1000, "Total assets should remain the same after upgrade"
        );

        uint256 newTotalSupply = migrationVault.totalSupply();
        assertEq(newTotalSupply, previousTotalSupply, "Total supply should remain the same after upgrade");

        uint256 newBalance = migrationVault.balanceOf(specificHolder);
        assertEq(newBalance, previousBalance, "Balance should remain the same after upgrade");

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

        // set allocator to bob
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), address(bob));

        // set strategy manager to admin for now
        vault_.grantRole(vault_.STRATEGY_MANAGER_ROLE(), address(ADMIN));

        // set provider
        vault_.setProvider(address(MC.PROVIDER));

        vault_.addAsset(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.WBNB), 18, false);
        vault_.addAsset(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SLISBNB), 18, false);
        vault_.addAsset(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.BNBX), 18, false);

        setApprovalRule(vault_, MC.SLISBNB, MC.STAKER_GATEWAY);
        setStakingRule(vault_, MC.SLISBNB);

        // allow transfers to admin for testing
        setTransferRule(vault_, MC.SLISBNB, ADMIN);

        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
    }

    function setTransferRule(KernelStrategy vault_, address contractAddress, address recipient) public {
        address[] memory allowList = new address[](1);
        allowList[0] = recipient;
        setTransferRule(vault_, contractAddress, allowList);
    }

    function setTransferRule(KernelStrategy vault_, address contractAddress, address[] memory allowList) public {
        bytes4 funcSig = bytes4(keccak256("transfer(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setApprovalRule(KernelStrategy vault_, address contractAddress, address spender) public {
        address[] memory allowList = new address[](1);
        allowList[0] = spender;
        setApprovalRule(vault_, contractAddress, allowList);
    }

    function setApprovalRule(KernelStrategy vault_, address contractAddress, address[] memory allowList) public {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setStakingRule(KernelStrategy vault_, address asset) public {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        setStakingRule(vault_, assets);
    }

    function setStakingRule(KernelStrategy vault_, address[] memory assets) public {
        bytes4 funcSig = bytes4(keccak256("stake(address,uint256,string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // since there is no verification for uints in the Guard.sol, setting the string param to uint256
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});
        vault_.setProcessorRule(MC.STAKER_GATEWAY, funcSig, rule);
    }

    function transferToAdmin(address asset, uint256 amount) public {
        address[] memory targets = new address[](1);
        targets[0] = asset;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("transfer(address,uint256)", ADMIN, amount);

        vm.prank(ADMIN);
        vault.processor(targets, values, data);

        vault.processAccounting();
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

        vm.prank(ADMIN);
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

    function getSlisBnb(uint256 amount) internal {
        // deposit BNB to SLISBNB through stake manager
        ISlisBnbStakeManager stakeManager = ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER);

        vm.deal(bob, amount * 2);

        vm.prank(bob);
        stakeManager.deposit{value: amount * 2}();

        IERC20 slisBnb = IERC20(MC.SLISBNB);
        assertGe(slisBnb.balanceOf(bob), amount, "Should have slisBnb");
    }

    function test_Vault_ynBNBk_deposit_slisBNB() public {
        uint256 amount = 100 ether;

        getSlisBnb(amount);

        depositIntoVault(MC.SLISBNB, amount);
    }

    function test_Vault_ynBNBk_withdraw_slisBNB() public {
        uint256 amount = 100 ether;

        getSlisBnb(amount);

        depositIntoVault(MC.SLISBNB, amount);

        IERC20 asset = IERC20(MC.SLISBNB);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 previewShares = vault.previewWithdrawAsset(MC.SLISBNB, amount);

        vm.prank(bob);
        uint256 shares = vault.withdrawAsset(MC.SLISBNB, amount, bob, bob);

        assertEq(shares, previewShares, "Shares should be equal to preview shares");

        uint256 afterVaultBalance = asset.balanceOf(address(vault));
        uint256 afterBobBalance = asset.balanceOf(bob);
        uint256 afterBobShares = vault.balanceOf(bob);

        assertEq(afterVaultBalance, beforeVaultBalance - amount, "Vault balance should decrease by amount");
        assertEq(afterBobBalance, beforeBobBalance + amount, "Bob balance should increase by amount");
        assertEq(afterBobShares, beforeBobShares - shares, "Bob shares should decrease by shares");
    }

    function test_Vault_ynBNBk_redeem_slisBNB() public {
        uint256 amount = 100 ether;

        getSlisBnb(amount);

        IERC20 asset = IERC20(MC.SLISBNB);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeBobBalance = asset.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 shares = depositIntoVault(MC.SLISBNB, amount);

        uint256 previewAssets = vault.previewRedeemAsset(MC.SLISBNB, shares);

        assertGt(asset.balanceOf(address(vault)), previewAssets, "Vault should have enough assets to withdraw");

        vm.prank(bob);
        uint256 assets = vault.redeemAsset(MC.SLISBNB, shares, bob, bob);

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

    function test_Vault_ynBNBk_deposit_and_stake_slisBNB() public {
        uint256 amount = 0.5 ether;

        getSlisBnb(amount);

        depositIntoVault(MC.SLISBNB, amount);

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SLISBNB);

        IERC20 asset = IERC20(MC.SLISBNB);

        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeKernelVaultBalance = asset.balanceOf(kernelVault);
        uint256 beforeTotalAssets = vault.totalAssets();

        stakeIntoKernel(MC.SLISBNB, amount);

        assertEq(
            asset.balanceOf(address(vault)), beforeVaultBalance - amount, "Vault should have the asset after deposit"
        );
        assertEq(
            asset.balanceOf(kernelVault),
            beforeKernelVaultBalance + amount,
            "KernelVault should have the asset after deposit"
        );
        assertEq(vault.totalAssets(), beforeTotalAssets, "Total assets should not change");
    }

    function test_Vault_ynBNBk_deposit_and_stake_and_withdraw_slisBNB() public {
        uint256 amount = 0.5 ether;

        getSlisBnb(amount);

        depositIntoVault(MC.SLISBNB, amount);

        IERC20 asset = IERC20(MC.SLISBNB);

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SLISBNB);

        {
            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeKernelVaultBalance = asset.balanceOf(kernelVault);
            uint256 beforeTotalAssets = vault.totalAssets();

            stakeIntoKernel(MC.SLISBNB, amount);

            assertEq(
                asset.balanceOf(address(vault)),
                beforeVaultBalance - amount,
                "Vault should have the asset after deposit"
            );
            assertEq(
                asset.balanceOf(kernelVault),
                beforeKernelVaultBalance + amount,
                "KernelVault should have the asset after deposit"
            );
            assertEq(vault.totalAssets(), beforeTotalAssets, "Total assets should not change");
        }

        {
            // remove any funds from the vault to test unstaking
            transferToAdmin(MC.SLISBNB, asset.balanceOf(address(vault)));

            uint256 beforeKernelVaultBalance = asset.balanceOf(kernelVault);
            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeBobBalance = asset.balanceOf(bob);
            uint256 beforeBobShares = vault.balanceOf(bob);

            uint256 assets = vault.previewRedeemAsset(MC.SLISBNB, beforeBobShares);

            vm.prank(bob);
            vault.withdrawAsset(MC.SLISBNB, assets, bob, bob);

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
            assertEqThreshold(afterBobShares, 0, 2000, "Bob shares should decrease by shares");
        }
    }

    function test_Vault_ynBNBk_deposit_and_stake_and_redeem_slisBNB() public {
        uint256 amount = 0.5 ether;

        getSlisBnb(amount);

        depositIntoVault(MC.SLISBNB, amount);

        IERC20 asset = IERC20(MC.SLISBNB);

        address kernelVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SLISBNB);

        {
            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeKernelVaultBalance = asset.balanceOf(kernelVault);
            uint256 beforeTotalAssets = vault.totalAssets();

            stakeIntoKernel(MC.SLISBNB, amount);

            assertEq(
                asset.balanceOf(address(vault)),
                beforeVaultBalance - amount,
                "Vault should have the asset after deposit"
            );
            assertEq(
                asset.balanceOf(kernelVault),
                beforeKernelVaultBalance + amount,
                "KernelVault should have the asset after deposit"
            );
            assertEq(vault.totalAssets(), beforeTotalAssets, "Total assets should not change");
        }

        {
            // remove any funds from the vault to test unstaking
            transferToAdmin(MC.SLISBNB, asset.balanceOf(address(vault)));

            uint256 beforeKernelVaultBalance = asset.balanceOf(kernelVault);
            uint256 beforeVaultBalance = asset.balanceOf(address(vault));
            uint256 beforeBobBalance = asset.balanceOf(bob);
            uint256 beforeBobShares = vault.balanceOf(bob);

            uint256 previewAssets = vault.previewRedeemAsset(MC.SLISBNB, beforeBobShares);

            vm.prank(bob);
            uint256 assets = vault.redeemAsset(MC.SLISBNB, beforeBobShares, bob, bob);

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
            assertEq(afterBobShares, 0, "Bob shares should decrease by shares");
        }
    }
}
