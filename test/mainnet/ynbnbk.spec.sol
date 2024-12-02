// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupKernelStrategy, Vault, IVault} from "test/mainnet/helpers/SetupKernelStrategy.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {ISlisBnbStakeManager} from "lib/yieldnest-vault/src/interface/external/lista/ISlisBnbStakeManager.sol";

contract VaultMainnetYnBNBkTest is Test, AssertUtils, MainnetActors {
    Vault public vault;

    function setUp() public {
        SetupKernelStrategy setup = new SetupKernelStrategy();
        (vault,,) = setup.deploy();

        vm.startPrank(ADMIN);

        setWBNBWithdrawRule();
        setYnBNBkDepositRule();
        setYnBNBkDepositAssetRule();

        vm.stopPrank();
    }

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = MC.BUFFER;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.buffer(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(ADMIN);
        vault.processor(targets, values, data);

        vault.processAccounting();
    }

    event Log(string, uint256);

    function test_Vault_ynBNBk_depositAndAllocate() public {
        // if (assets < 0.1 ether) return;
        // if (assets > 100_000 ether) return;

        address bob = address(1776);

        vm.deal(bob, 10000 ether);

        address assetAddress = MC.SLISBNB;

        // deposit BNB to SLISBNB through stake manager
        ISlisBnbStakeManager stakeManager = ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER);

        uint256 assets = 100 ether;

        vm.prank(bob);
        stakeManager.deposit{value: assets * 2}();

        vm.startPrank(bob);
        // previous vault total Assets
        uint256 previousTotalAssets = vault.totalAssets();

        IERC20(assetAddress).approve(address(vault), assets);
        uint256 depositedShares = vault.depositAsset(assetAddress, assets, bob);

        uint256 assetBalance = IERC20(assetAddress).balanceOf(address(vault));
        assertEq(assetBalance, assets, "Vault should hold the deposited assets");

        vm.startPrank(PROCESSOR);
        processApproveAsset(assetAddress, assets, MC.YNBNBk);
        processDepositYnBNBk(assetAddress, assets);

        uint256 ynBnbkBalance = IERC20(MC.YNBNBk).balanceOf(address(vault));
        vm.stopPrank();

        uint256 newTotalAssets = vault.totalAssets();
        assertApproxEqAbs(
            newTotalAssets,
            previousTotalAssets + stakeManager.convertSnBnbToBnb(assets),
            100,
            "New total assets should equal deposit amount plus original total assets"
        );
    }

    function processApproveAsset(address asset, uint256 amount, address target) public {
        address[] memory targets = new address[](1);
        targets[0] = asset;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", target, amount);

        vault.processor(targets, values, data);
    }

    function processWithrdawWBNB(uint256 assets) public {
        // convert WBNB to BNB
        address[] memory targets = new address[](1);
        targets[0] = MC.WBNB;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("withdraw(uint256)", assets);

        vault.processor(targets, values, data);
    }

    function processDepositYnBNBk(address assetAddress, uint256 assets) public {
        // deposit BNB to ynBNBk
        address[] memory targets = new address[](1);
        targets[0] = MC.YNBNBk;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("depositAsset(address,uint256,address)", assetAddress, assets, address(vault));

        vault.processor(targets, values, data);
    }

    function setWBNBWithdrawRule() internal {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault.setProcessorRule(MC.WBNB, funcSig, rule);
    }

    function setYnBNBkDepositRule() internal {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(vault); // receiver

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault.setProcessorRule(MC.YNBNBk, funcSig, rule);
    }

    function setYnBNBkDepositAssetRule() internal {
        bytes4 funcSig = bytes4(keccak256("depositAsset(address,uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        address[] memory tokenAllowList = new address[](3);
        tokenAllowList[0] = MC.WBNB;
        tokenAllowList[1] = MC.SLISBNB;
        tokenAllowList[2] = MC.BNBX;

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: tokenAllowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(vault); // receiver

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault.setProcessorRule(MC.YNBNBk, funcSig, rule);
    }
}
