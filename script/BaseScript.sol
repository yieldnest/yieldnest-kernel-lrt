// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {BscActors, ChapelActors, IActors} from "script/Actors.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";
import {VaultUtils} from "script/VaultUtils.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {BTCRateProvider, TestnetBTCRateProvider} from "src/module/BTCRateProvider.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

abstract contract BaseScript is Script, VaultUtils {
    using stdJson for string;

    uint256 public minDelay;
    IActors public actors;
    IContracts public contracts;

    TimelockController public timelock;
    KernelStrategy public vault;
    KernelStrategy public implementation;
    IProvider public rateProvider;

    error UnsupportedChain();
    error InvalidSetup();

    // needs to be overriden by child script
    function symbol() public virtual returns (string memory);

    function _setup() public {
        if (block.chainid == 97) {
            minDelay = 10 seconds;
            ChapelActors _actors = new ChapelActors();
            actors = IActors(_actors);
            contracts = IContracts(new ChapelContracts());
        }

        if (block.chainid == 56) {
            minDelay = 1 days;
            BscActors _actors = new BscActors();
            actors = IActors(_actors);
            contracts = IContracts(new BscContracts());
        }
    }

    function _verifySetup() public view {
        if (block.chainid != 56 && block.chainid != 97) {
            revert UnsupportedChain();
        }
        if (address(actors) == address(0) || address(contracts) == address(0) || address(rateProvider) == address(0) || address(timelock) == address(0)) {
            revert InvalidSetup();
        }
    }

    function _deployTimelockController() internal {
        address[] memory proposers = new address[](2);
        proposers[0] = actors.PROPOSER_1();
        proposers[1] = actors.PROPOSER_2();

        address[] memory executors = new address[](2);
        executors[0] = actors.EXECUTOR_1();
        executors[1] = actors.EXECUTOR_2();

        address admin = actors.ADMIN();

        timelock = new TimelockController(minDelay, proposers, executors, admin);
    }

    function _configureDefaultRoles(KernelStrategy vault_) internal {
        if (actors.ADMIN() == address(0) || address(timelock) == address(0)) {
            revert InvalidSetup();
        }

        // set admin roles
        vault_.grantRole(vault_.DEFAULT_ADMIN_ROLE(), actors.ADMIN());
        vault_.grantRole(vault_.PROCESSOR_ROLE(), actors.ADMIN());
        vault_.grantRole(vault_.PAUSER_ROLE(), actors.ADMIN());
        vault_.grantRole(vault_.UNPAUSER_ROLE(), actors.ADMIN());
        vault_.grantRole(vault_.DEPOSIT_MANAGER_ROLE(), actors.ADMIN());
        vault_.grantRole(vault_.ALLOCATOR_MANAGER_ROLE(), actors.ADMIN());

        // set timelock roles
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), address(timelock));
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), address(timelock));
        vault_.grantRole(vault_.BUFFER_MANAGER_ROLE(), address(timelock));
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), address(timelock));
        vault_.grantRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), address(timelock));
    }

    function _configureTemporaryRoles(KernelStrategy vault_) internal {
        vault_.grantRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.DEPOSIT_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.ALLOCATOR_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.UNPAUSER_ROLE(), msg.sender);
    }

    function _renounceTemporaryRoles(KernelStrategy vault_) internal {
        vault_.renounceRole(vault_.DEFAULT_ADMIN_ROLE(), msg.sender);
        vault_.renounceRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.DEPOSIT_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.ALLOCATOR_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.PROCESSOR_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.PROVIDER_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.ASSET_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.UNPAUSER_ROLE(), msg.sender);
    }

    function _saveDeployment() internal {
        vm.serializeAddress(symbol(), "deployer", msg.sender);
        vm.serializeAddress(symbol(), string.concat(symbol(), "-proxy"), address(vault));
        vm.serializeAddress(symbol(), "rateProvider", address(rateProvider));
        string memory jsonOutput =
            vm.serializeAddress(symbol(), string.concat(symbol(), "-implementation"), address(implementation));

        vm.writeJson(
            jsonOutput, string.concat("./deployments/", symbol(), "-", Strings.toString(block.chainid), ".json")
        );
    }
}
