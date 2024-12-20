// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {KernelStrategy} from "src/KernelStrategy.sol";

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {IValidator} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {BaseScript} from "script/BaseScript.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

import {Test} from "lib/forge-std/src/Test.sol";

import {BaseVaultViewer} from "lib/yieldnest-vault/src/utils/BaseVaultViewer.sol";

// FOUNDRY_PROFILE=mainnet forge script VerifyYnBTCkStrategy
abstract contract BaseVerifyScript is BaseScript, Test {
    function _verifyDefaultRoles(KernelStrategy vault_) internal view {
        // verify timelock roles
        assertEq(vault_.hasRole(vault_.PROVIDER_MANAGER_ROLE(), address(timelock)), true);
        assertEq(vault_.hasRole(vault_.ASSET_MANAGER_ROLE(), address(timelock)), true);
        assertEq(vault_.hasRole(vault_.BUFFER_MANAGER_ROLE(), address(timelock)), true);
        assertEq(vault_.hasRole(vault_.PROCESSOR_MANAGER_ROLE(), address(timelock)), true);
        assertEq(vault_.hasRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), address(timelock)), true);
        assertEq(ProxyUtils.getProxyAdmin(address(vault_)), address(timelock));

        // verify actors roles
        assertEq(vault_.hasRole(vault_.PROCESSOR_ROLE(), actors.PROCESSOR()), true);
        assertEq(vault_.hasRole(vault_.DEFAULT_ADMIN_ROLE(), ProxyUtils.getProxyAdmin(address(vault_))), true);
        assertEq(vault_.hasRole(vault_.PAUSER_ROLE(), actors.PAUSER()), true);
        assertEq(vault_.hasRole(vault_.UNPAUSER_ROLE(), actors.UNPAUSER()), true);
        assertEq(vault_.hasRole(vault_.DEPOSIT_MANAGER_ROLE(), actors.DEPOSIT_MANAGER()), true);
        assertEq(vault_.hasRole(vault_.ALLOCATOR_MANAGER_ROLE(), actors.ALLOCATOR_MANAGER()), true);
    }

    function _verifyTemporaryRoles(KernelStrategy vault_) internal view {
        assertEq(vault_.hasRole(vault_.PROVIDER_MANAGER_ROLE(), deployer), false);
        assertEq(vault_.hasRole(vault_.ASSET_MANAGER_ROLE(), deployer), false);
        assertEq(vault_.hasRole(vault_.BUFFER_MANAGER_ROLE(), deployer), false);
        assertEq(vault_.hasRole(vault_.PROCESSOR_MANAGER_ROLE(), deployer), false);
        assertEq(vault_.hasRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), deployer), false);

        assertEq(vault_.hasRole(vault_.DEFAULT_ADMIN_ROLE(), deployer), false);
        assertEq(vault_.hasRole(vault_.PROCESSOR_ROLE(), deployer), false);
        assertEq(vault_.hasRole(vault_.PAUSER_ROLE(), deployer), false);
        assertEq(vault_.hasRole(vault_.UNPAUSER_ROLE(), deployer), false);
        assertEq(vault_.hasRole(vault_.DEPOSIT_MANAGER_ROLE(), deployer), false);
        assertEq(vault_.hasRole(vault_.ALLOCATOR_MANAGER_ROLE(), deployer), false);
    }

    function _verifyViewer() internal view {
        assertEq(address(viewer.getVault()), address(vault));
        BaseVaultViewer.AssetInfo[] memory assets = viewer.getAssets();
        address[] memory assertsList = vault.getAssets();
        assertEq(assets.length, assertsList.length);

        for (uint256 i = 0; i < assets.length; i++) {
            assertEq(assets[i].asset, assertsList[i]);
            assertEq(assets[i].canDeposit, vault.getAsset(assertsList[i]).active);
        }
    }

    function _verifyDepositRule(KernelStrategy vault_, address contractAddress, address asset) internal view {
        address[] memory assets = new address[](1);
        assets[0] = asset;

        _verifyDepositRule(vault_, contractAddress, assets);
    }

    function _verifyDepositRule(KernelStrategy vault_, address contractAddress, address[] memory assets)
        internal
        view
    {
        bytes4 funcSig = bytes4(keccak256("deposit(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function _verifyApprovalRule(KernelStrategy vault_, address contractAddress, address spender) internal view {
        address[] memory allowList = new address[](1);
        allowList[0] = spender;

        _verifyApprovalRule(vault_, contractAddress, allowList);
    }

    function _verifyApprovalRule(KernelStrategy vault_, address contractAddress, address[] memory allowList)
        internal
        view
    {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function _verifyStakingRule(KernelStrategy vault_, address contractAddress, address asset) internal view {
        address[] memory assets = new address[](1);
        assets[0] = asset;

        _verifyStakingRule(vault_, contractAddress, assets);
    }

    function _verifyStakingRule(KernelStrategy vault_, address contractAddress, address[] memory assets)
        internal
        view
    {
        bytes4 funcSig = bytes4(keccak256("stake(address,uint256,string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function _verifyClisStakingRule(KernelStrategy vault_, address contractAddress) internal view {
        bytes4 funcSig = bytes4(keccak256("stakeClisBNB(string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function _verifyClisUnstakingRule(KernelStrategy vault_, address contractAddress) internal view {
        bytes4 funcSig = bytes4(keccak256("unstakeClisBNB(uint256,string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function _verifyUnstakingRule(KernelStrategy vault_, address contractAddress, address asset) internal view {
        address[] memory assets = new address[](1);
        assets[0] = asset;

        _verifyUnstakingRule(vault_, contractAddress, assets);
    }

    function _verifyUnstakingRule(KernelStrategy vault_, address contractAddress, address[] memory assets)
        internal
        view
    {
        bytes4 funcSig = bytes4(keccak256("unstake(address,uint256,string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function _verifyProcessorRule(
        KernelStrategy vault_,
        address contractAddress,
        bytes4 funcSig,
        IVault.FunctionRule memory expectedResult
    ) internal view {
        IVault.FunctionRule memory rule = vault_.getProcessorRule(contractAddress, funcSig);

        // Add assertions
        assertEq(rule.isActive, expectedResult.isActive, "isActive does not match");
        assertEq(rule.paramRules.length, expectedResult.paramRules.length, "paramRules length does not match");

        for (uint256 i = 0; i < rule.paramRules.length; i++) {
            assertEq(
                uint256(rule.paramRules[i].paramType),
                uint256(expectedResult.paramRules[i].paramType),
                "paramType does not match"
            );
            assertEq(rule.paramRules[i].isArray, expectedResult.paramRules[i].isArray, "isArray does not match");
            assertEq(
                rule.paramRules[i].allowList.length,
                expectedResult.paramRules[i].allowList.length,
                "allowList length does not match"
            );

            for (uint256 j = 0; j < rule.paramRules[i].allowList.length; j++) {
                assertEq(
                    rule.paramRules[i].allowList[j],
                    expectedResult.paramRules[i].allowList[j],
                    "allowList element does not match"
                );
            }
        }
    }
}
