// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";

import {BscActors, ChapelActors, IActors} from "script/Actors.sol";
import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";
import {VaultUtils} from "script/VaultUtils.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {BTCRateProvider} from "src/module/BTCRateProvider.sol";

import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployYnBTCkStrategy --sender 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract DeployYnBTCkStrategy is Script, VaultUtils {
    IActors public actors;

    IContracts public contracts;

    KernelStrategy public vault;

    BTCRateProvider public rateProvider;

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

        rateProvider = new BTCRateProvider();

        deployVault();

        vm.stopBroadcast();
    }

    function deployVault() internal returns (KernelStrategy) {
        KernelStrategy implementation = new KernelStrategy();

        bytes memory initData = abi.encodeWithSelector(
            KernelStrategy.initialize.selector, msg.sender, "YieldNest Restaked BTC - Kernel", "ynBTCk", 18, 0, false
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
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), contracts.YNBTCX());

        // set strategy manager to admin for now
        vault_.grantRole(vault_.STRATEGY_MANAGER_ROLE(), actors.ADMIN());

        // set roles to msg.sender for now
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), msg.sender);
        vault_.grantRole(vault_.UNPAUSER_ROLE(), msg.sender);

        // set provider
        vault_.setProvider(address(rateProvider));

        vault_.addAsset(contracts.BTCB(), true);
        vault_.addAsset(contracts.SOLVBTC(), true);
        vault_.addAsset(contracts.SOLVBTC_BNN(), true);

        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.BTCB()), 18, false);
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.SOLVBTC()), 18, false);
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.SOLVBTC_BNN()), 18, false);

        setApprovalRule(vault_, contracts.BTCB(), contracts.STAKER_GATEWAY());
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.BTCB());

        setApprovalRule(vault_, contracts.SOLVBTC(), contracts.STAKER_GATEWAY());
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.SOLVBTC());

        setApprovalRule(vault_, contracts.SOLVBTC_BNN(), contracts.STAKER_GATEWAY());
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.SOLVBTC_BNN());

        vault_.unpause();

        vault_.processAccounting();

        vault_.renounceRole(vault_.DEFAULT_ADMIN_ROLE(), msg.sender);
        vault_.renounceRole(vault_.PROCESSOR_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.PROVIDER_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.ASSET_MANAGER_ROLE(), msg.sender);
        vault_.renounceRole(vault_.UNPAUSER_ROLE(), msg.sender);
    }
}
