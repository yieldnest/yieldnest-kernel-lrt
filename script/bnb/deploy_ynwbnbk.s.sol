// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";

import {BscActors, ChapelActors, IActors} from "script/Actors.sol";
import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";
import {VaultUtils} from "script/VaultUtils.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {BNBRateProvider} from "src/module/BNBRateProvider.sol";

import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployYnWBNBkStrategy --sender 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract DeployYnWBNBkStrategy is Script, VaultUtils {
    IActors public actors;

    IContracts public contracts;

    KernelStrategy public vault;

    BNBRateProvider public rateProvider;
    KernelStrategy public implementation;

    error UnsupportedChain();
    error InvalidSender();

    function symbol() public pure returns (string memory) {
        return "ynWBNBk";
    }

    function run() public {
        if (block.chainid == 97) {
            ChapelActors _actors = new ChapelActors();
            actors = IActors(_actors);
            contracts = IContracts(new ChapelContracts());
        }

        if (block.chainid == 56) {
            BscActors _actors = new BscActors();
            actors = IActors(_actors);
            contracts = IContracts(new BscContracts());
        }

        vm.startBroadcast();

        rateProvider = new BNBRateProvider();
        deploy();
        saveDeployment();

        vm.stopBroadcast();
    }

    function deploy() internal returns (KernelStrategy) {
        implementation = new KernelStrategy();

        bytes memory initData = abi.encodeWithSelector(
            KernelStrategy.initialize.selector, msg.sender, "YieldNest WBNB Buffer - Kernel", "ynWBNBk", 18, 0, true
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(actors.ADMIN()), initData);

        vault = KernelStrategy(payable(address(proxy)));

        configureVault(vault);

        return vault;
    }

    function configureVault(KernelStrategy vault_) internal {
        // set processor to admin for now

        vault_.grantRole(vault_.DEFAULT_ADMIN_ROLE(), actors.ADMIN());
        vault_.grantRole(vault_.PROCESSOR_ROLE(), actors.ADMIN());
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), actors.PROVIDER_MANAGER());
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), actors.ASSET_MANAGER());
        vault_.grantRole(vault_.BUFFER_MANAGER_ROLE(), actors.BUFFER_MANAGER());
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), actors.PROCESSOR_MANAGER());
        vault_.grantRole(vault_.PAUSER_ROLE(), actors.PAUSER());
        vault_.grantRole(vault_.UNPAUSER_ROLE(), actors.UNPAUSER());

        // set allocator to ynbnbx
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), contracts.YNBNBX());

        vault_.grantRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), actors.KERNEL_DEPENDENCY_MANAGER());
        vault_.grantRole(vault_.DEPOSIT_MANAGER_ROLE(), actors.DEPOSIT_MANAGER());
        vault_.grantRole(vault_.ALLOCATOR_MANAGER_ROLE(), actors.ALLOCATOR_MANAGER());

        // set roles to msg.sender for now
        vault_.grantRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.DEPOSIT_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.ALLOCATOR_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.UNPAUSER_ROLE(), msg.sender);

        vault_.setProvider(address(rateProvider));
        vault_.setHasAllocator(true);
        vault_.setStakerGateway(contracts.STAKER_GATEWAY());
        vault_.setSyncDeposit(true);
        vault_.setSyncWithdraw(true);

        vault_.addAsset(contracts.WBNB(), true);
        vault_.addAssetWithDecimals(IStakerGateway(contracts.STAKER_GATEWAY()).getVault(contracts.WBNB()), 18, false);

        setApprovalRule(vault_, contracts.WBNB(), contracts.STAKER_GATEWAY());
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.WBNB());

        vault_.unpause();

        vault_.processAccounting();

        vault_.renounceRole(vault_.DEFAULT_ADMIN_ROLE(), msg.sender);
        vault_.renounceRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.DEPOSIT_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.ALLOCATOR_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.PROCESSOR_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.PROVIDER_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.ASSET_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.UNPAUSER_ROLE(), msg.sender);
    }

    function saveDeployment() internal {
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
