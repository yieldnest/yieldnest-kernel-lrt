// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {KernelStrategy} from "src/KernelStrategy.sol";

import {IActors} from "lib/yieldnest-vault/script/BaseScript.sol";
import {BaseVerifyScript, IVault} from "lib/yieldnest-vault/script/BaseVerifyScript.sol";
import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {IValidator} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";
import {BscActors, ChapelActors, IKernelActors} from "script/KernelActors.sol";

// FOUNDRY_PROFILE=mainnet forge script KernelVerifyScript
abstract contract KernelVerifyScript is BaseVerifyScript {
    IKernelActors public actors_;
    KernelStrategy public vault_;

    function _setup() public virtual override {
        deployer = msg.sender;

        if (block.chainid == 97) {
            minDelay = 10 seconds;
            ChapelActors _actors = new ChapelActors();
            actors = IActors(address(_actors));
            actors_ = IKernelActors(address(actors));
            contracts = IContracts(new ChapelContracts());
        }

        if (block.chainid == 56) {
            minDelay = 1 days;
            BscActors _actors = new BscActors();
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
        assertEq(vault.hasRole(keccak256("KERNEL_DEPENDENCY_MANAGER_ROLE"), address(timelock)), true);

        // verify actors_ roles
        assertEq(vault.hasRole(keccak256("DEPOSIT_MANAGER_ROLE"), actors_.DEPOSIT_MANAGER()), true);
        assertEq(vault.hasRole(keccak256("ALLOCATOR_MANAGER_ROLE"), actors_.ALLOCATOR_MANAGER()), true);
    }

    function _verifyTemporaryRoles() internal view override {
        super._verifyTemporaryRoles();

        assertEq(vault.hasRole(keccak256("KERNEL_DEPENDENCY_MANAGER_ROLE"), deployer), false);

        assertEq(vault.hasRole(keccak256("DEPOSIT_MANAGER_ROLE"), deployer), false);
        assertEq(vault.hasRole(keccak256("ALLOCATOR_MANAGER_ROLE"), deployer), false);
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
