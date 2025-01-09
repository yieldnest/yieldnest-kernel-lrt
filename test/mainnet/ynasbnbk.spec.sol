// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {Vault} from "lib/yieldnest-vault/src/Vault.sol";

import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetKernelActors} from "script/KernelActors.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";

import {IAccessControl} from
    "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {VaultUtils} from "lib/yieldnest-vault/script/VaultUtils.sol";
import {IWBNB} from "src/interface/external/IWBNB.sol";
import {IKernelConfig} from "src/interface/external/kernel/IKernelConfig.sol";
import {IKernelVault} from "src/interface/external/kernel/IKernelVault.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {BNBRateProvider} from "src/module/BNBRateProvider.sol";

import {VaultKernelUtils} from "script/VaultKernelUtils.sol";
import {KernelVaultViewer} from "src/utils/KernelVaultViewer.sol";
import {BaseVaultViewer} from "src/utils/KernelVaultViewer.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";

contract YnAsBNBkTest is Test, AssertUtils, MainnetKernelActors, EtchUtils, VaultUtils, VaultKernelUtils {
    KernelStrategy public vault;
    BNBRateProvider public kernelProvider;
    IStakerGateway public stakerGateway;
    KernelVaultViewer public viewer;
    IKernelVault public kernelVault;
    IERC20 public wbnb;
    IERC20 public asbnb;
    IERC20 public slisbnb;

    address public alice = address(0xA11ce);

     function setUp() public {
        kernelProvider = new BNBRateProvider();
        etchProvider(address(kernelProvider));

        vault = deployBuffer();
        viewer = KernelVaultViewer(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new KernelVaultViewer()),
                        ADMIN,
                        abi.encodeWithSelector(BaseVaultViewer.initialize.selector, address(vault))
                    )
                )
            )
        );

        etchBuffer(address(vault));
        stakerGateway = IStakerGateway(MC.STAKER_GATEWAY);
        kernelVault = IKernelVault(stakerGateway.getVault(MC.ASBNB));
        wbnb = IERC20(MC.WBNB);
        asbnb = IERC20(MC.ASBNB);
        slisbnb = IERC20(MC.SLISBNB);
        
        address config = kernelVault.getConfig();
        bytes32 role = IKernelConfig(config).ROLE_MANAGER();

        vm.prank(MC.KERNEL_CONFIG_ADMIN);
        IKernelConfig(config).grantRole(role, address(this));

        IKernelVault(kernelVault).setDepositLimit(type(uint256).max);
    }

    function deployBuffer() internal returns (KernelStrategy) {
        // Deploy implementation contract
        KernelStrategy implementation = new KernelStrategy();

        // Deploy transparent proxy
        bytes memory initData = abi.encodeWithSelector(
            Vault.initialize.selector, ADMIN, "YieldNest AsBNB Buffer - Kernel", 18, 0, true, false
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(ADMIN), initData);

        // Cast proxy to KernelStrategy type
        vault = KernelStrategy(payable(address(proxy)));

        assertEq(vault.symbol(), "ynAsBNBk");

        configureBuffer(vault);

        return vault;
    }

    function configureBuffer(KernelStrategy vault_) internal {
        vm.startPrank(ADMIN);

        vault_.grantRole(vault_.PROCESSOR_ROLE(), PROCESSOR);
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault_.grantRole(vault_.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault_.grantRole(vault_.PAUSER_ROLE(), PAUSER);
        vault_.grantRole(vault_.UNPAUSER_ROLE(), UNPAUSER);

        // set allocator to alice
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), address(alice));

        // set strategy manager to admin for now
        vault_.grantRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), ADMIN);
        vault_.grantRole(vault_.DEPOSIT_MANAGER_ROLE(), ADMIN);
        vault_.grantRole(vault_.ALLOCATOR_MANAGER_ROLE(), ADMIN);

        vault_.setProvider(address(MC.PROVIDER));

        vault_.setHasAllocator(true);
        vault_.setStakerGateway(MC.STAKER_GATEWAY);
        vault_.setSyncDeposit(true);
        vault_.setSyncWithdraw(true);

        vault_.addAsset(MC.WBNB, true);
        vault_.addAssetWithDecimals(address(kernelVault), 18, true);
        assertNotEq(address(kernelVault), address(0));
        setApprovalRule(vault_, MC.WBNB, address(stakerGateway));
        setStakingRule(vault_, address(stakerGateway), MC.ASBNB);
        setStakingRule(vault_, address(stakerGateway), MC.WBNB);
        setUnstakingRule(vault_, address(stakerGateway), MC.ASBNB);

        // wbnb
        setWethDepositRule(vault, MC.WBNB);
        setWethDepositRule(vault, MC.ASBNB);
        setWethWithdrawRule(vault, MC.WBNB);
        setWithdrawAssetRule(vault, address(stakerGateway), MC.ASBNB);


        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
    }
}