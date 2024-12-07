// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";

import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";

import {KernelRateProvider} from "src/module/KernelRateProvider.sol";

import {VaultUtils} from "script/VaultUtils.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";

contract SetupKernelStrategy is Test, AssertUtils, MainnetActors, EtchUtils, VaultUtils {
    KernelRateProvider public kernelProvider;
    KernelStrategy public vault;

    function deploy() public returns (KernelStrategy, KernelRateProvider) {
        kernelProvider = new KernelRateProvider();
        etchProvider(address(kernelProvider));

        KernelStrategy implementation = new KernelStrategy();
        bytes memory initData = abi.encodeWithSelector(
            KernelStrategy.initialize.selector,
            MainnetActors.ADMIN,
            "YieldNest Restaked BNB - Kernel",
            "ynWBNBk",
            18,
            0,
            true
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(MainnetActors.ADMIN), initData);

        vault = KernelStrategy(payable(address(proxy)));
        configureKernelStrategy(vault);
        return (vault, kernelProvider);
    }

    function configureKernelStrategy(KernelStrategy vault_) internal {
        vm.startPrank(ADMIN);

        vault_.grantRole(vault_.PROCESSOR_ROLE(), PROCESSOR);
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault_.grantRole(vault_.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault_.grantRole(vault_.PAUSER_ROLE(), PAUSER);
        vault_.grantRole(vault_.UNPAUSER_ROLE(), UNPAUSER);

        // since we're not testing the max vault, we'll set the admin as the allocator role
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), address(ADMIN));

        // set strategy manager to admin for now
        vault_.grantRole(vault_.STRATEGY_MANAGER_ROLE(), address(ADMIN));

        vault_.setProvider(address(kernelProvider));

        vault_.setStakerGateway(MC.STAKER_GATEWAY);

        vault_.setSyncDeposit(true);

        vault_.addAsset(MC.WBNB, true);
        vault_.addAsset(MC.SLISBNB, true);

        // set deposit rules
        setDepositRule(vault_, MC.WBNB, address(vault_));

        // set approval rules
        setApprovalRule(vault_, address(vault_), MC.STAKER_GATEWAY);

        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
    }
}
