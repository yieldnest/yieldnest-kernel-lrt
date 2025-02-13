// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Vault} from "lib/yieldnest-vault/src/Vault.sol";
import {MockSTETH} from "lib/yieldnest-vault/test/unit/mocks/MockST_ETH.sol";
import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetKernelActors} from "script/KernelActors.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {BNBRateProvider} from "src/module/BNBRateProvider.sol";

import {MockERC20LowDecimals} from "../mocks/MockERC20LowDecimals.sol";
import {MockStakerGateway} from "../mocks/MockStakerGateway.sol";
import {MockRateProvider} from "test/unit/mocks/MockRateProvider.sol";

import {VaultUtils} from "lib/yieldnest-vault/script/VaultUtils.sol";
import {VaultKernelUtils} from "script/VaultKernelUtils.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {EtchUtils} from "test/unit/helpers/EtchUtils.sol";

contract SetupKernelStrategy is Test, AssertUtils, MainnetKernelActors, EtchUtils, VaultKernelUtils, VaultUtils {
    KernelStrategy public vault;
    BNBRateProvider public provider;

    WETH9 public wbnb;
    MockSTETH public slisbnb;
    WETH9 public bnbx;
    MockERC20LowDecimals public btc;
    IStakerGateway public mockGateway;
    MockRateProvider public lowDecimalProvider;

    address public alice = address(0x0a11ce);
    address public bob = address(0x0b0b);
    address public chad = address(0x0cad);

    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function deploy() public {
        mockAll();
        provider = new BNBRateProvider();
        KernelStrategy implementation = new KernelStrategy();
        bytes memory initData = abi.encodeWithSelector(
            Vault.initialize.selector, ADMIN, "YieldNest Restaked BNB - Kernel", "ynWBNBk", 18, 0, true, false
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(ADMIN), initData);

        vault = KernelStrategy(payable(address(proxy)));

        wbnb = WETH9(payable(MC.WBNB));
        slisbnb = MockSTETH(payable(MC.SLISBNB));
        bnbx = WETH9(payable(MC.BNBX));
        btc = new MockERC20LowDecimals("BTC", "BTC"); // decimals = 8

        lowDecimalProvider = new MockRateProvider();
        lowDecimalProvider.addRate(address(wbnb), 1e18); // 10 ** 18 wbnb = 10 ** 18 base
        lowDecimalProvider.addRate(address(bnbx), 1e18); // 10 ** 18 bnbx = 10 ** 18 base
        lowDecimalProvider.addRate(address(slisbnb), 1e18); // 10 ** 18 slisbnb = 10 ** 18 base
        lowDecimalProvider.addRate(address(btc), 1e18); // 10 ** 8 btc = 10 ** 18 base

        address[] memory assets = new address[](3);
        assets[0] = address(wbnb);
        assets[1] = address(slisbnb);
        assets[2] = address(bnbx);

        mockGateway = IStakerGateway(address(new MockStakerGateway(assets)));

        configureKernelStrategy();
    }

    function configureKernelStrategy() internal {
        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        // set allocator to alice for testing
        vault.grantRole(vault.ALLOCATOR_ROLE(), address(alice));

        vault.grantRole(vault.KERNEL_DEPENDENCY_MANAGER_ROLE(), ADMIN);
        vault.grantRole(vault.DEPOSIT_MANAGER_ROLE(), ADMIN);
        vault.grantRole(vault.ALLOCATOR_MANAGER_ROLE(), ADMIN);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), ADMIN);

        // set provider
        vault.setProvider(address(provider));

        // set staker gateway
        vault.setStakerGateway(address(mockGateway));

        // set has allocator
        vault.setHasAllocator(true);

        // by default, we don't sync deposits or withdraws
        // we set it for individual tests
        // vault.setSyncDeposit(true);
        // vault.setSyncWithdraw(true);

        // add assets
        vault.addAsset(MC.WBNB, true);
        vault.addAsset(MC.SLISBNB, true);
        vault.addAsset(MC.BNBX, true);
        vault.addAsset(address(btc), true);

        // by default, we don't set any rules

        vault.unpause();

        vm.stopPrank();

        vault.processAccounting();
    }
}
