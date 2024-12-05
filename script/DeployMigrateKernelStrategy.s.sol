// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";

import {BscActors, ChapelActors, IActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {VaultUtils} from "script/VaultUtils.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {MigratedKernelStrategy} from "src/MigratedKernelStrategy.sol";
import {KernelRateProvider} from "src/module/KernelRateProvider.sol";

import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {
    ITransparentUpgradeableProxy,
    ProxyAdmin
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployMigrateKernelStrategy --sender 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract DeployMigrateKernelStrategy is Script, VaultUtils {
    IActors public actors;

    IContracts public contracts;

    KernelStrategy public vault;

    KernelRateProvider public rateProvider;

    error UnsupportedChain();
    error InvalidSender();

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

        rateProvider = new KernelRateProvider();

        deployMigrateVault();

        vm.stopBroadcast();
    }

    function deployMigrateVault() internal returns (KernelStrategy) {
        address vaultAddress = contracts.YNBNBK();

        MigratedKernelStrategy implemention = new MigratedKernelStrategy();

        ProxyAdmin proxyAdmin = ProxyAdmin(ProxyUtils.getProxyAdmin(vaultAddress));

        if (proxyAdmin.owner() != msg.sender) {
            revert InvalidSender();
        }

        // TODO: handle if proxy admin owner is a time lock controller

        MigratedKernelStrategy.Asset[] memory assets = new MigratedKernelStrategy.Asset[](3);

        assets[0] = MigratedKernelStrategy.Asset({asset: MC.WBNB, active: false});
        assets[1] = MigratedKernelStrategy.Asset({asset: MC.SLISBNB, active: true});
        assets[2] = MigratedKernelStrategy.Asset({asset: MC.BNBX, active: true});

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(vaultAddress),
            address(implemention),
            abi.encodeWithSelector(
                MigratedKernelStrategy.initializeAndMigrate.selector,
                msg.sender,
                "YieldNest Restaked BNB - Kernel",
                "ynBNBk",
                18,
                assets,
                MC.STAKER_GATEWAY,
                false,
                true
            )
        );

        vault = KernelStrategy(payable(address(vaultAddress)));
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

        // set strategy manager to admin for now
        vault_.grantRole(vault_.STRATEGY_MANAGER_ROLE(), actors.ADMIN());

        // set roles to msg.sender for now
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.UNPAUSER_ROLE(), msg.sender);

        // set provider
        vault_.setProvider(address(rateProvider));

        vault_.addAsset(IStakerGateway(contracts.STAKER_GATEWAY()).getVault(contracts.WBNB()), false);
        vault_.addAsset(IStakerGateway(contracts.STAKER_GATEWAY()).getVault(contracts.SLISBNB()), false);
        vault_.addAsset(IStakerGateway(contracts.STAKER_GATEWAY()).getVault(contracts.BNBX()), false);

        setApprovalRule(vault_, contracts.SLISBNB(), contracts.STAKER_GATEWAY());
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.SLISBNB());

        vault_.unpause();

        vault_.processAccounting();

        vault_.renounceRole(vault_.DEFAULT_ADMIN_ROLE(), msg.sender);
        vault_.renounceRole(vault_.PROCESSOR_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.PROVIDER_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.ASSET_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.UNPAUSER_ROLE(), msg.sender);
    }
}
