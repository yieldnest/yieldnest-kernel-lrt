// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";
import {MainnetActors} from "script/Actors.sol";
import {BaseVaultViewer, KernelVaultViewer} from "src/utils/KernelVaultViewer.sol";

import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IStakerGateway, KernelStrategy} from "src/KernelStrategy.sol";

import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {BNBRateProvider} from "src/module/BNBRateProvider.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";

contract YnWBNBkBufferTest is Test, AssertUtils, MainnetActors, EtchUtils {
    KernelStrategy public vault;
    BNBRateProvider public kernelProvider;
    IKernelVault public kernelVault;
    KernelVaultViewer public viewer;

    address public bob = address(0xB0B);

    function setUp() public {
        kernelProvider = new BNBRateProvider();
        etchProvider(address(kernelProvider));

        vault = deployBuffer();
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

        etchBuffer(address(vault));

        address config = kernelVault.getConfig();
        bytes32 role = IKernelConfig(config).ROLE_MANAGER();

        vm.prank(MC.KERNEL_CONFIG_ADMIN);
        IKernelConfig(config).grantRole(role, address(this));

        IKernelVault(kernelVault).setDepositLimit(type(uint256).max);
    }

    function deployBuffer() internal returns (KernelStrategy) {
        // Deploy implementation contract
        KernelStrategy implementation = new KernelStrategy();

        // Deploy transparent proxy
        bytes memory initData = abi.encodeWithSelector(
            KernelStrategy.initialize.selector,
            MainnetActors.ADMIN,
            "YieldNest BNB Buffer - Kernel",
            "ynWBNBk",
            18,
            0,
            true,
            false
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(MainnetActors.ADMIN), initData);

        // Cast proxy to KernelStrategy type
        vault = KernelStrategy(payable(address(proxy)));

        assertEq(vault.symbol(), "ynWBNBk");

        configureBuffer(vault);

        return vault;
    }

    function configureBuffer(KernelStrategy vault_) internal {
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
        vault_.grantRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), ADMIN);
        vault_.grantRole(vault_.DEPOSIT_MANAGER_ROLE(), ADMIN);
        vault_.grantRole(vault_.ALLOCATOR_MANAGER_ROLE(), ADMIN);

        vault_.setProvider(address(MC.PROVIDER));

        vault_.setHasAllocator(true);
        vault_.setStakerGateway(MC.STAKER_GATEWAY);
        vault_.setSyncDeposit(true);
        vault_.setSyncWithdraw(true);

        kernelVault = IKernelVault(IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.WBNB));
        assertNotEq(address(kernelVault), address(0));

        vault_.addAsset(MC.WBNB, true);
        vault_.addAssetWithDecimals(address(kernelVault), 18, false);

        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
    }

    function test_Buffer_Vault_ERC20_view_functions() public view {
        // Test the name function
        assertEq(vault.name(), "YieldNest BNB Buffer - Kernel", "Vault name should be 'YieldNest BNB Buffer - Kernel'");

        // Test the symbol function
        assertEq(vault.symbol(), "ynWBNBk", "Vault symbol should be 'ynWBNBk'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        vault.totalSupply();
    }

    function test_Buffer_Vault_ERC4626_view_functions() public view {
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
        assertEqThreshold(convertedAssets, amount, 3, "Converted assets should be close to amount deposited");

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
        assertEq(assets.length, 2, "There should be two assets in the vault");
        assertEq(assets[0], MC.WBNB, "First asset should be WBNB");
        assertEq(assets[1], address(kernelVault), "Second asset should be the WBNB kernel vault");
    }

    function test_Buffer_Vault_ERC4626_deposit(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);
        depositIntoBuffer(amount);
    }

    function depositIntoBuffer(uint256 amount) internal returns (uint256) {
        WETH9 wbnb = WETH9(payable(MC.WBNB));
        uint256 depositLimit = kernelVault.getDepositLimit();
        assertGt(depositLimit, amount, "Deposit limit should be greater than amount");

        uint256 beforeTotalAssets = vault.totalAssets();
        uint256 beforeTotalShares = vault.totalSupply();
        uint256 beforeVaultBalance = wbnb.balanceOf(address(vault));
        uint256 beforeKernelVaultBalance = wbnb.balanceOf(address(kernelVault));
        uint256 beforeBobBalance = wbnb.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);
        uint256 beforeMaxWithdraw = viewer.maxWithdrawAsset(MC.WBNB, bob);
        assertEq(beforeMaxWithdraw, 0, "Bob should have no max withdraw before deposit");

        vm.deal(bob, amount);
        vm.prank(bob);
        wbnb.deposit{value: amount}();

        assertEq(wbnb.balanceOf(bob), beforeBobBalance + amount);

        vm.prank(bob);
        wbnb.approve(address(vault), amount);

        uint256 previewShares = vault.previewDeposit(amount);

        // Test the deposit function
        vm.prank(bob);
        uint256 shares = vault.deposit(amount, bob);

        assertEq(previewShares, shares, "Preview shares should be equal to shares");

        assertEq(
            vault.totalAssets(), beforeTotalAssets + amount, "Total assets should increase by the amount deposited"
        );
        assertEq(
            vault.totalSupply(), beforeTotalShares + shares, "Total shares should increase by the amount deposited"
        );
        assertEq(
            wbnb.balanceOf(address(vault)),
            beforeVaultBalance,
            "Vault should have the same amount of WBNB after deposit"
        );
        assertEq(
            wbnb.balanceOf(address(kernelVault)),
            beforeKernelVaultBalance + amount,
            "KernelVault should have funds after deposit"
        );
        assertEq(wbnb.balanceOf(bob), beforeBobBalance, "Bob should have the same amount of WBNB after deposit");
        assertEq(vault.balanceOf(bob), beforeBobShares + shares, "Bob should have shares after deposit");
        assertEq(
            viewer.maxWithdrawAsset(MC.WBNB, bob),
            beforeMaxWithdraw + amount,
            "Bob should have max withdraw after deposit"
        );
        assertEq(
            viewer.maxWithdrawAsset(address(kernelVault), address(bob)),
            0,
            "Bob should have no max withdraw for inactive asset after deposit"
        );

        return shares;
    }

    function test_Buffer_Vault_ERC4626_withdraw(uint256 amount) public {
        amount = bound(amount, 10, 100_000 ether);

        WETH9 wbnb = WETH9(payable(MC.WBNB));

        uint256 beforeVaultBalance = wbnb.balanceOf(address(vault));
        uint256 beforeKernelVaultBalance = wbnb.balanceOf(address(kernelVault));
        uint256 beforeBobBalance = wbnb.balanceOf(bob);
        uint256 beforeBobShares = vault.balanceOf(bob);

        uint256 shares = depositIntoBuffer(amount);

        vm.prank(bob);
        vault.withdraw(shares, bob, bob);

        assertEq(
            wbnb.balanceOf(address(vault)),
            beforeVaultBalance,
            "Vault should have the same amount of WBNB after withdraw"
        );
        assertEq(
            wbnb.balanceOf(address(kernelVault)),
            beforeKernelVaultBalance,
            "KernelVault should have funds after withdraw"
        );
        assertEq(wbnb.balanceOf(bob), beforeBobBalance + amount, "Bob should have the amount deposited after withdraw");
        assertEq(vault.balanceOf(bob), beforeBobShares, "Bob should have no shares after withdraw");
    }
}
