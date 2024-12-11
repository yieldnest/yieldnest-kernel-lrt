// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {BscActors, ChapelActors, IActors} from "script/Actors.sol";
import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";
import {VaultUtils} from "script/VaultUtils.sol";

import {TransparentUpgradeableProxy as TUP} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";

import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import {BaseVaultViewer} from "lib/yieldnest-vault/src/utils/BaseVaultViewer.sol";

abstract contract BaseScript is Script, VaultUtils {
    using stdJson for string;

    uint256 public minDelay;
    IActors public actors;
    IContracts public contracts;

    address public deployer;
    TimelockController public timelock;
    IProvider public rateProvider;
    KernelStrategy public vault;
    KernelStrategy public implementation;
    BaseVaultViewer public viewer;
    BaseVaultViewer public viewerImplementation;

    error UnsupportedChain();
    error InvalidSetup();

    // needs to be overriden by child script
    function symbol() public view virtual returns (string memory);

    function _setup() public {
        deployer = msg.sender;

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
        if (
            address(actors) == address(0) || address(contracts) == address(0) || address(rateProvider) == address(0)
                || address(timelock) == address(0)
        ) {
            revert InvalidSetup();
        }
    }

    function _deployViewer() internal {
        if (address(vault) == address(0)) {
            revert InvalidSetup();
        }

        viewerImplementation = new BaseVaultViewer();

        bytes memory initData = abi.encodeWithSelector(BaseVaultViewer.initialize.selector, address(vault));

        TUP proxy = new TUP(address(viewerImplementation), actors.ADMIN(), initData);

        viewer = BaseVaultViewer(payable(address(proxy)));
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
        vault_.grantRole(vault_.PAUSER_ROLE(), actors.PAUSER());
        vault_.grantRole(vault_.UNPAUSER_ROLE(), actors.UNPAUSER());
        vault_.grantRole(vault_.DEPOSIT_MANAGER_ROLE(), actors.DEPOSIT_MANAGER());
        vault_.grantRole(vault_.ALLOCATOR_MANAGER_ROLE(), actors.ALLOCATOR_MANAGER());

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

    function _loadDeployment() internal {
        string memory jsonInput = vm.readFile(_deploymentFilePath());

        deployer = address(vm.parseJsonAddress(jsonInput, ".deployer"));
        timelock = TimelockController(payable(address(vm.parseJsonAddress(jsonInput, ".timelock"))));
        rateProvider = IProvider(payable(address(vm.parseJsonAddress(jsonInput, ".rateProvider"))));
        vault = KernelStrategy(payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxy")))));
        implementation = KernelStrategy(
            payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-implementation"))))
        );
    }

    function _deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", symbol(), "-", Strings.toString(block.chainid), ".json");
    }

    function _saveDeployment() internal {
        // minDelay
        vm.serializeAddress(symbol(), "deployer", msg.sender);
        vm.serializeAddress(symbol(), "admin", actors.ADMIN());
        vm.serializeAddress(symbol(), "timelock", address(timelock));
        vm.serializeAddress(symbol(), "rateProvider", address(rateProvider));
        vm.serializeAddress(symbol(), "viewer-proxy", address(viewer));
        vm.serializeAddress(symbol(), "viewer-implementation", address(viewerImplementation));
        vm.serializeAddress(symbol(), string.concat(symbol(), "-proxy"), address(vault));
        string memory jsonOutput =
            vm.serializeAddress(symbol(), string.concat(symbol(), "-implementation"), address(implementation));

        vm.writeJson(jsonOutput, _deploymentFilePath());
    }
}
