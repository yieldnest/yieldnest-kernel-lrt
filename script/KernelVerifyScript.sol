// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {KernelStrategy} from "src/KernelStrategy.sol";

import {console} from "lib/forge-std/src/console.sol";
import {IActors} from "lib/yieldnest-vault/script/BaseScript.sol";
import {BaseVerifyScript, IVault} from "lib/yieldnest-vault/script/BaseVerifyScript.sol";
import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {IValidator} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";
import {IKernelActors, MainnetKernelActors, TestnetKernelActors} from "script/KernelActors.sol";

// FOUNDRY_PROFILE=mainnet forge script KernelVerifyScript
abstract contract KernelVerifyScript is BaseVerifyScript {
    IKernelActors public actors_;
    KernelStrategy public vault_;

    function _setup() public virtual override {
        deployer = msg.sender;

        if (block.chainid == 97) {
            minDelay = 10 seconds;
            TestnetKernelActors _actors = new TestnetKernelActors();
            actors = IActors(address(_actors));
            actors_ = IKernelActors(address(actors));
            contracts = IContracts(new ChapelContracts());
        }

        if (block.chainid == 56) {
            minDelay = 1 days;
            MainnetKernelActors _actors = new MainnetKernelActors();
            actors = IActors(address(_actors));
            actors_ = IKernelActors(address(actors));
            contracts = IContracts(new BscContracts());
        }

        if (address(vault) != address(0)) {
            vault_ = KernelStrategy(payable(address(vault)));
        }
    }

    function _verifyDefaultRoles() internal view override {
        super._verifyDefaultRoles();

        // verify timelock roles
        bool timelockRole = vault_.hasRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), address(timelock));
        console.log(
            timelockRole ? "\u2705" : "\u274C", "timelock has KERNEL_DEPENDENCY_MANAGER_ROLE:", address(timelock)
        );
        assertEq(timelockRole, true);

        // verify actors_ roles
        bool depositManagerRole = vault_.hasRole(vault_.DEPOSIT_MANAGER_ROLE(), actors_.DEPOSIT_MANAGER());
        console.log(
            depositManagerRole ? "\u2705" : "\u274C",
            "DEPOSIT_MANAGER has DEPOSIT_MANAGER_ROLE:",
            actors_.DEPOSIT_MANAGER()
        );
        assertEq(depositManagerRole, true);

        bool allocationManagerRole = vault_.hasRole(vault_.ALLOCATOR_MANAGER_ROLE(), actors_.ALLOCATOR_MANAGER());
        console.log(
            allocationManagerRole ? "\u2705" : "\u274C",
            "ALLOCATOR_MANAGER has ALLOCATOR_MANAGER_ROLE:",
            actors_.ALLOCATOR_MANAGER()
        );
        assertEq(allocationManagerRole, true);
    }

    function _verifyTemporaryRoles() internal view override {
        super._verifyTemporaryRoles();

        bool kernelDependencyManagerRole = vault_.hasRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), deployer);
        console.log(
            !kernelDependencyManagerRole ? "\u2705" : "\u274C",
            "deployer has renounced KERNEL_DEPENDENCY_MANAGER_ROLE:",
            deployer
        );
        assertEq(kernelDependencyManagerRole, false);

        bool depositManagerRole = vault_.hasRole(vault_.DEPOSIT_MANAGER_ROLE(), deployer);
        console.log(!depositManagerRole ? "\u2705" : "\u274C", "deployer has renounced DEPOSIT_MANAGER_ROLE:", deployer);
        assertEq(depositManagerRole, false);

        bool allocatorManagerRole = vault_.hasRole(vault_.ALLOCATOR_MANAGER_ROLE(), deployer);
        console.log(
            !allocatorManagerRole ? "\u2705" : "\u274C", "deployer has renounced ALLOCATOR_MANAGER_ROLE:", deployer
        );
        assertEq(allocatorManagerRole, false);
    }

    function _verifyStakingRule(IVault v, address contractAddress, address asset) internal view {
        address[] memory assets = new address[](1);
        assets[0] = asset;

        _verifyStakingRule(v, contractAddress, assets);
    }

    function _verifyStakingRule(IVault v, address contractAddress, address[] memory assets) internal view {
        bytes4 funcSig = bytes4(keccak256("stake(address,uint256,string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(v, contractAddress, funcSig, rule);
    }

    function _verifyClisStakingRule(IVault v, address contractAddress) internal view {
        bytes4 funcSig = bytes4(keccak256("stakeClisBNB(string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(v, contractAddress, funcSig, rule);
    }

    function _verifyClisUnstakingRule(IVault v, address contractAddress) internal view {
        bytes4 funcSig = bytes4(keccak256("unstakeClisBNB(uint256,string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(v, contractAddress, funcSig, rule);
    }

    function _verifyUnstakingRule(IVault v, address contractAddress, address asset) internal view {
        address[] memory assets = new address[](1);
        assets[0] = asset;

        _verifyUnstakingRule(v, contractAddress, assets);
    }

    function _verifyUnstakingRule(IVault v, address contractAddress, address[] memory assets) internal view {
        bytes4 funcSig = bytes4(keccak256("unstake(address,uint256,string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(v, contractAddress, funcSig, rule);
    }
}
