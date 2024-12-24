// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";
import {BscActors, ChapelActors, IKernelActors} from "script/KernelActors.sol";
import {VaultKernelUtils} from "script/VaultKernelUtils.sol";

import {BaseScript, IActors} from "lib/yieldnest-vault/script/BaseScript.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {KernelVaultViewer} from "src/utils/KernelVaultViewer.sol";

abstract contract BaseKernelScript is BaseScript, VaultKernelUtils {
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

    function _deployViewer() internal {
        address _impl = address(new KernelVaultViewer());
        _deployViewer(_impl);
    }

    function _configureDefaultRoles() internal virtual override {
        super._configureDefaultRoles();

        vault_ = KernelStrategy(payable(address(vault)));

        // set admin roles
        vault.grantRole(keccak256("DEPOSIT_MANAGER_ROLE"), actors_.DEPOSIT_MANAGER());
        vault.grantRole(keccak256("ALLOCATOR_MANAGER_ROLE"), actors_.ALLOCATOR_MANAGER());

        // set timelock roles
        vault.grantRole(keccak256("KERNEL_DEPENDENCY_MANAGER_ROLE"), address(timelock));
    }

    function _configureTemporaryRoles() internal virtual override {
        super._configureTemporaryRoles();

        vault.grantRole(keccak256("KERNEL_DEPENDENCY_MANAGER_ROLE"), msg.sender);
        vault.grantRole(keccak256("DEPOSIT_MANAGER_ROLE"), msg.sender);
        vault.grantRole(keccak256("ALLOCATOR_MANAGER_ROLE"), msg.sender);
    }

    function _renounceTemporaryRoles() internal virtual override {
        super._renounceTemporaryRoles();

        vault.renounceRole(keccak256("KERNEL_DEPENDENCY_MANAGER_ROLE"), msg.sender);
        vault.renounceRole(keccak256("DEPOSIT_MANAGER_ROLE"), msg.sender);
        vault.renounceRole(keccak256("ALLOCATOR_MANAGER_ROLE"), msg.sender);
    }
}
