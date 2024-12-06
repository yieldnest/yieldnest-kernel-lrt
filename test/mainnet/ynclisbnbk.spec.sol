// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IERC20, ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";

import {ISlisBnbStakeManager} from "lib/yieldnest-vault/src/interface/external/lista/ISlisBnbStakeManager.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";

import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {KernelClisStrategy} from "src/KernelClisStrategy.sol";
import {MigratedKernelStrategy} from "src/MigratedKernelStrategy.sol";

import {VaultUtils} from "script/VaultUtils.sol";
import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {KernelRateProvider} from "src/module/KernelRateProvider.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";

contract KernelClisStrategyTest is Test, AssertUtils, MainnetActors, EtchUtils, VaultUtils {
    KernelClisStrategy public vault;
    KernelRateProvider public kernelProvider;
    IStakerGateway public stakerGateway;

    address public bob = address(0xB0B);

    function setUp() public {
        kernelProvider = new KernelRateProvider();
        etchProvider(address(kernelProvider));

        vault = deployClisBNBk();

        stakerGateway = IStakerGateway(MC.STAKER_GATEWAY);
        vm.label(MC.STAKER_GATEWAY, "staker gateway");
        vm.label(address(vault), "kernel Strategy");
        vm.label(address(kernelProvider), "kernel strategy provider");
    }

    function deployClisBNBk() public returns(KernelClisStrategy vault) {
        KernelClisStrategy implementation = new KernelClisStrategy();
         bytes memory initData = abi.encodeWithSelector(
            KernelClisStrategy.initialize.selector,
            MainnetActors.ADMIN,
            "YieldNest Restaked slisBNB - Kernel",
            "ynclisWBNBk",
            18,
            0,
            true
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(MainnetActors.ADMIN), initData);

        vault = KernelClisStrategy(payable(address(proxy)));
        configureKernelClisStrategy(vault);
    }

    function configureKernelClisStrategy(KernelClisStrategy vault_) public {
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

        // set deposit rules
        setDepositRule(vault_, MC.WBNB, address(vault_));

        // set approval rules
        setApprovalRule(vault_, address(vault_), MC.STAKER_GATEWAY);

        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
    }
}