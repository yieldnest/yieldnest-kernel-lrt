// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";

import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetKernelActors} from "script/KernelActors.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";

import {VaultUtils} from "lib/yieldnest-vault/script/VaultUtils.sol";
import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {BNBRateProvider} from "src/module/BNBRateProvider.sol";

import {VaultKernelUtils} from "script/VaultKernelUtils.sol";
import {KernelVaultViewer} from "src/utils/KernelVaultViewer.sol";
import {BaseVaultViewer} from "src/utils/KernelVaultViewer.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";

import {ISlisBnbStakeManager} from "lib/yieldnest-vault/src/interface/external/lista/ISlisBnbStakeManager.sol";
import {IAsBnbMinter} from "src/interface/external/astherus/IAsBnbMinter.sol";

contract YnAsBNBkTest is Test, AssertUtils, MainnetKernelActors, EtchUtils, VaultUtils, VaultKernelUtils {
    KernelStrategy public vault;
    BNBRateProvider public kernelProvider;
    IStakerGateway public stakerGateway;
    KernelVaultViewer public viewer;
    IKernelVault public asbnbKernelVault;

    ISlisBnbStakeManager public slisBnbStakeManager;
    IAsBnbMinter public asBnbMinter;

    IERC20 public wbnb;
    IERC20 public asbnb;
    IERC20 public slisbnb;

    address public alice = address(0xA11ce);

    uint256 public minMintAmount = 0.001 ether;

    function setUp() public {
        kernelProvider = new BNBRateProvider();
        etchProvider(address(kernelProvider));

        stakerGateway = IStakerGateway(MC.STAKER_GATEWAY);
        asbnbKernelVault = IKernelVault(stakerGateway.getVault(MC.ASBNB));
        assertNotEq(address(asbnbKernelVault), address(0));
        slisBnbStakeManager = ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER);
        asBnbMinter = IAsBnbMinter(MC.AS_BNB_MINTER);

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

        wbnb = IERC20(MC.WBNB);
        asbnb = IERC20(MC.ASBNB);
        slisbnb = IERC20(MC.SLISBNB);

        address config = asbnbKernelVault.getConfig();
        bytes32 role = IKernelConfig(config).ROLE_MANAGER();

        vm.prank(MC.KERNEL_CONFIG_ADMIN);
        IKernelConfig(config).grantRole(role, address(this));

        IKernelVault(asbnbKernelVault).setDepositLimit(type(uint256).max);

        assertEq(asBnbMinter.minMintAmount(), minMintAmount, "asbnb minter should have min mint amount");
    }

    function deploy() internal returns (KernelStrategy) {
        // Deploy implementation contract
        KernelStrategy implementation = new KernelStrategy();

        // Deploy transparent proxy
        bytes memory initData = abi.encodeWithSelector(
            Vault.initialize.selector, ADMIN, "YieldNest Restaked asBNB - Kernel", "ynAsBNBk", 18, 0, true, false
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(ADMIN), initData);

        // Cast proxy to KernelStrategy type
        vault = KernelStrategy(payable(address(proxy)));

        assertEq(vault.symbol(), "ynAsBNBk");

        configure(vault);

        return vault;
    }

    function configure(KernelStrategy vault_) internal {
        vm.startPrank(ADMIN);

        vault_.grantRole(vault_.PROCESSOR_ROLE(), PROCESSOR);
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault_.grantRole(vault_.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault_.grantRole(vault_.PAUSER_ROLE(), PAUSER);
        vault_.grantRole(vault_.UNPAUSER_ROLE(), UNPAUSER);
        vault_.grantRole(vault_.FEE_MANAGER_ROLE(), FEE_MANAGER);

        // set allocator to alice
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), address(alice));

        // set strategy manager to admin for now
        vault_.grantRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), ADMIN);
        vault_.grantRole(vault_.DEPOSIT_MANAGER_ROLE(), ADMIN);
        vault_.grantRole(vault_.ALLOCATOR_MANAGER_ROLE(), ADMIN);

        vault_.setProvider(address(MC.PROVIDER));

        vault_.setHasAllocator(true);
        vault_.setStakerGateway(MC.STAKER_GATEWAY);
        vault_.setSyncDeposit(true);
        vault_.setSyncWithdraw(true);

        vault_.addAsset(MC.WBNB, false);
        vault_.addAsset(MC.SLISBNB, false);
        vault_.addAsset(MC.ASBNB, true);

        vault_.addAssetWithDecimals(address(asbnbKernelVault), 18, false);

        // bnb <=> wbnb
        setWethDepositRule(vault, MC.WBNB);
        setWethWithdrawRule(vault, MC.WBNB);

        // wbnb => slisbnb
        setSlisDepositRule(vault, MC.SLIS_BNB_STAKE_MANAGER);

        // slisbnb <=> asbnb
        setApprovalRule(vault, MC.SLISBNB, MC.AS_BNB_MINTER);
        setAstherusMintRule(vault, MC.AS_BNB_MINTER);
        setAstherusBurnRule(vault, MC.AS_BNB_MINTER);

        // asbnb <=> kernel
        setApprovalRule(vault_, MC.ASBNB, address(stakerGateway));
        setStakingRule(vault_, address(stakerGateway), MC.ASBNB);
        setUnstakingRule(vault_, address(stakerGateway), MC.ASBNB);

        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
    }

    function test_Vault_ERC20_view_functions() public view {
        // Test the name function
        assertEq(
            vault.name(),
            "YieldNest Restaked asBNB - Kernel",
            "Vault name should be 'YieldNest Restaked asBNB - Kernel'"
        );

        // Test the symbol function
        assertEq(vault.symbol(), "ynAsBNBk", "Vault symbol should be 'ynAsBNBk'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        vault.totalSupply();
    }

    function test_Vault_ERC4626_view_functions() public view {
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

        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 4, "There should be two assets in the vault");
        assertEq(assets[0], MC.WBNB, "First asset should be WBNB");
        assertEq(assets[1], MC.SLISBNB, "Second asset should be SLISBNB");
        assertEq(assets[2], MC.ASBNB, "Third asset should be ASBNB");
        assertEq(assets[3], address(asbnbKernelVault), "Fourth asset should be ASBNB Kernel Vault");
    }

    function _unwrapWBNB(uint256 amount) internal {
        address[] memory targets = new address[](1);
        targets[0] = address(wbnb);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("withdraw(uint256)", amount);

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        vault.processAccounting();
    }

    function _depositBNBForSlis(uint256 amount) internal {
        address[] memory targets = new address[](1);
        targets[0] = MC.SLIS_BNB_STAKE_MANAGER;

        uint256[] memory values = new uint256[](1);
        values[0] = amount;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit()");

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        vault.processAccounting();
    }

    function _mintAsBnb(uint256 amount) internal {
        address[] memory targets = new address[](2);
        targets[0] = MC.SLISBNB;
        targets[1] = MC.AS_BNB_MINTER;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.AS_BNB_MINTER, amount);
        data[1] = abi.encodeWithSignature("mintAsBnb(uint256)", amount);

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        vault.processAccounting();
    }

    function _stakeAsBnb(uint256 amount) internal {
        address[] memory targets = new address[](2);
        targets[0] = address(asbnb);
        targets[1] = MC.STAKER_GATEWAY;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.STAKER_GATEWAY, amount);
        data[1] = abi.encodeWithSignature("stake(address,uint256,string)", address(asbnb), amount, "");

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        vault.processAccounting();
    }

    function _unstakeAsBnb(uint256 amount) internal {
        address[] memory targets = new address[](1);
        targets[0] = MC.STAKER_GATEWAY;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("unstake(address,uint256,string)", address(asbnb), amount, "");

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        vault.processAccounting();
    }

    function test_Vault_wbnb_to_asBNB_and_stake_unstake_asbnb(uint256 amount) public {
        uint256 minMintAmountInBNB = slisBnbStakeManager.convertSnBnbToBnb(minMintAmount) + 1;
        amount = bound(amount, minMintAmountInBNB, 100_000 ether);

        deal(MC.WBNB, address(vault), amount);

        assertEq(wbnb.balanceOf(address(vault)), amount, "vault should have wbnb");

        vault.processAccounting();

        assertEq(vault.totalAssets(), amount, "vault should have full supply");

        _unwrapWBNB(amount);

        assertEq(wbnb.balanceOf(address(vault)), 0, "vault should have no wbnb");
        assertEq(address(vault).balance, amount, "vault should have bnb");
        assertEq(vault.totalAssets(), amount, "vault should have full supply");

        _depositBNBForSlis(amount);

        assertApproxEqRel(vault.totalAssets(), amount, 1e14, "vault should have full supply");
        assertEq(address(vault).balance, 0, "vault should have no bnb");
        uint256 slisBnbAmount = slisBnbStakeManager.convertBnbToSnBnb(amount);
        assertApproxEqRel(slisbnb.balanceOf(address(vault)), slisBnbAmount, 1e14, "vault should have slisbnb");

        _mintAsBnb(slisbnb.balanceOf(address(vault)));

        assertApproxEqRel(vault.totalAssets(), amount, 1e14, "vault should have full supply");
        assertEq(slisbnb.balanceOf(address(vault)), 0, "vault should have no slisbnb");
        uint256 asBnbAmount = asBnbMinter.convertToAsBnb(slisBnbAmount);
        assertApproxEqRel(asbnb.balanceOf(address(vault)), asBnbAmount, 1e14, "vault should have asbnb");

        _stakeAsBnb(asbnb.balanceOf(address(vault)));

        assertApproxEqRel(vault.totalAssets(), amount, 1e14, "vault should have full supply");
        assertEq(asbnb.balanceOf(address(vault)), 0, "vault should have no asbnb");

        _unstakeAsBnb(stakerGateway.balanceOf(MC.ASBNB, address(vault)));

        assertApproxEqRel(vault.totalAssets(), amount, 1e14, "vault should have full supply");
        assertApproxEqRel(asbnb.balanceOf(address(vault)), asBnbAmount, 1e14, "vault should have asbnb");
    }

    function test_Vault_deposit_asbnb(uint256 amount) public {
        amount = bound(amount, minMintAmount, 100_000 ether);

        deal(MC.ASBNB, address(alice), amount);

        vm.startPrank(alice);
        IERC20(MC.ASBNB).approve(address(vault), amount);
        uint256 shares = vault.depositAsset(MC.ASBNB, amount, alice);
        vm.stopPrank();

        vault.processAccounting();

        uint256 slisBnbAmount = asBnbMinter.convertToTokens(amount);
        uint256 bnbAmount = slisBnbStakeManager.convertSnBnbToBnb(slisBnbAmount);

        assertApproxEqRel(vault.totalAssets(), bnbAmount, 1e14, "vault should have full supply");
        assertEq(vault.totalSupply(), shares, "vault should have full supply");
        assertEq(asbnb.balanceOf(address(vault)), 0, "vault should have asbnb");
        assertEq(
            stakerGateway.balanceOf(address(asbnb), address(vault)), amount, "asbnb kernel vault should have asbnb"
        );
    }

    function test_Vault_withdraw_asbnb(uint256 amount) public {
        amount = bound(amount, minMintAmount, 100_000 ether);

        deal(MC.ASBNB, address(alice), amount);

        vm.startPrank(alice);
        IERC20(MC.ASBNB).approve(address(vault), amount);
        uint256 shares = vault.depositAsset(MC.ASBNB, amount, alice);
        vm.stopPrank();

        vault.processAccounting();

        uint256 slisBnbAmount = asBnbMinter.convertToTokens(amount);
        uint256 bnbAmount = slisBnbStakeManager.convertSnBnbToBnb(slisBnbAmount);

        assertApproxEqRel(vault.totalAssets(), bnbAmount, 1e14, "vault should have full supply");
        assertEq(vault.totalSupply(), shares, "vault should have full supply");
        assertEq(asbnb.balanceOf(address(vault)), 0, "vault should have asbnb");
        assertEq(
            stakerGateway.balanceOf(address(asbnb), address(vault)), amount, "asbnb kernel vault should have asbnb"
        );

        uint256 maxWithdraw = vault.maxWithdrawAsset(MC.ASBNB, alice);

        assertApproxEqRel(maxWithdraw, amount, 1e14, "max withdraw should be equal to amount");

        vm.startPrank(alice);
        uint256 burntShares = vault.withdrawAsset(MC.ASBNB, maxWithdraw, alice, alice);
        vm.stopPrank();

        vault.processAccounting();

        assertEq(vault.totalAssets(), amount - maxWithdraw, "vault should have no assets");
        assertEq(vault.totalSupply(), shares - burntShares, "vault should have no shares");
        assertEq(asbnb.balanceOf(address(alice)), maxWithdraw, "alice should have asbnb");
    }
}
