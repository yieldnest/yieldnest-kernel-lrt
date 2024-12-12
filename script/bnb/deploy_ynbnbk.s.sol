// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {IValidator} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {MigratedKernelStrategy} from "src/MigratedKernelStrategy.sol";
import {BNBRateProvider, TestnetBNBRateProvider} from "src/module/BNBRateProvider.sol";

// import {console} from "forge-std/console.sol";
import {AccessControlUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {
    ITransparentUpgradeableProxy,
    ProxyAdmin
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {BaseScript} from "script/BaseScript.sol";
import {BatchScript, Operation, Transaction} from "script/BatchScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {console} from "lib/forge-std/src/console.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployYnBNBkStrategy --sig "run(bool)" <true/false> --sender
// 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract DeployYnBNBkStrategy is BaseScript, BatchScript {
    address public vaultAddress;
    ProxyAdmin public proxyAdmin;

    bytes32 public constant SALT = keccak256("yieldnest.vault.kernel.bnb");

    error InvalidSender();
    error AdminNotTimelockController();

    function symbol() public pure override returns (string memory) {
        return "ynBNBk";
    }

    function deployRateProvider() internal {
        if (block.chainid == 97) {
            rateProvider = IProvider(new TestnetBNBRateProvider());
        }

        if (block.chainid == 56) {
            rateProvider = IProvider(new BNBRateProvider());
        }
    }

    function run() public {
        runWithOption(true);
    }

    function runWithOption(bool isSafeTx) public {
        vm.startBroadcast();

        _setup();

        // load deployment if it exists (tx scheduled)
        _loadDeployment();

        if (address(rateProvider).code.length == 0) {
            deployRateProvider();
        }

        vaultAddress = contracts.YNBNBK();
        proxyAdmin = ProxyAdmin(ProxyUtils.getProxyAdmin(vaultAddress));
        timelock = TimelockController(payable(proxyAdmin.owner()));

        if (address(timelock).code.length == 0) {
            revert AdminNotTimelockController();
        }

        _verifySetup();

        deployMigrateVault(isSafeTx);

        if (address(viewer).code.length == 0) {
            _deployViewer();
        }

        _saveDeployment();

        vm.stopBroadcast();
    }

    function deployMigrateVault(bool isSafeTx) internal {
        implementation = KernelStrategy(payable(address(new MigratedKernelStrategy())));

        MigratedKernelStrategy.Asset[] memory assets = new MigratedKernelStrategy.Asset[](3);

        assets[0] = MigratedKernelStrategy.Asset({asset: contracts.WBNB(), active: false});
        assets[1] = MigratedKernelStrategy.Asset({asset: contracts.SLISBNB(), active: true});
        assets[2] = MigratedKernelStrategy.Asset({asset: contracts.BNBX(), active: true});

        bytes memory initData = abi.encodeWithSelector(
            MigratedKernelStrategy.initializeAndMigrate.selector,
            actors.ADMIN(),
            "YieldNest Restaked BNB - Kernel",
            symbol(),
            18,
            assets,
            contracts.STAKER_GATEWAY(),
            false,
            true,
            0,
            true
        );

        if (isSafeTx) {
            deployMigrateVaultAsSafe(initData);
        } else {
            deployMigrateVaultAsEOA(initData);
        }
    }

    function deployMigrateVaultAsSafe(bytes memory initData) internal isBatch(actors.ADMIN()) {
        vault = KernelStrategy(payable(address(vaultAddress)));
        // create upgrade call transaction
        bytes memory upgradeData = abi.encodeWithSelector(
            proxyAdmin.upgradeAndCall.selector,
            abi.encode(ITransparentUpgradeableProxy(vaultAddress), implementation, initData)
        );

        bool hasProcessorRole = timelock.hasRole(timelock.PROPOSER_ROLE(), actors.ADMIN());
        if (!hasProcessorRole) {
            revert InvalidSender();
        }

        bytes32 operationHash = timelock.hashOperation(address(proxyAdmin), 0, upgradeData, bytes32(0), SALT);

        if (timelock.isOperationReady(operationHash)) {
            // execute and configure
            bytes memory executeData =
                abi.encodeWithSelector(timelock.execute.selector, address(proxyAdmin), 0, upgradeData, bytes32(0), SALT);
            addToBatch(address(timelock), 0, executeData);

            configureVaultAsSafe();
            return;
        }

        if (timelock.isOperationDone(operationHash)) {
            console.log("Deployment Complete");
            return;
        }

        if (timelock.isOperationPending(operationHash)) {
            console.log("Deployment Pending");
            return;
        }

        bytes memory scheduleData = abi.encodeWithSelector(
            timelock.schedule.selector, address(proxyAdmin), 0, upgradeData, bytes32(0), SALT, minDelay
        );

        Transaction memory txInfo =
            Transaction({operation: Operation.CALL, to: address(timelock), value: 0, data: scheduleData});

        saveTransaction("schedule", txInfo);
    }

    function deployMigrateVaultAsEOA(bytes memory initData) internal {
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(vaultAddress), address(implementation), initData);

        vault = KernelStrategy(payable(address(vaultAddress)));
        configureVaultAsEOA();
    }

    function configureVaultAsEOA() internal {
        _configureDefaultRoles(vault);
        _configureTemporaryRoles(vault);

        // set provider
        vault.setProvider(address(rateProvider));

        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());

        vault.addAssetWithDecimals(stakerGateway.getVault(contracts.WBNB()), 18, false);
        vault.addAssetWithDecimals(stakerGateway.getVault(contracts.SLISBNB()), 18, false);
        vault.addAssetWithDecimals(stakerGateway.getVault(contracts.BNBX()), 18, false);

        setApprovalRule(vault, contracts.SLISBNB(), contracts.STAKER_GATEWAY());
        setStakingRule(vault, contracts.STAKER_GATEWAY(), contracts.SLISBNB());

        vault.unpause();

        vault.processAccounting();

        _renounceTemporaryRoles(vault);
    }

    function configureVaultAsSafe() internal {
        // set default roles
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("DEFAULT_ADMIN_ROLE"), actors.ADMIN()
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("PROCESSOR_ROLE"), actors.ADMIN()
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("PAUSER_ROLE"), actors.PAUSER()
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("UNPAUSER_ROLE"), actors.UNPAUSER()
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("DEPOSIT_MANAGER_ROLE"), actors.DEPOSIT_MANAGER()
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector,
                keccak256("ALLOCATOR_MANAGER_ROLE"),
                actors.ALLOCATOR_MANAGER()
            )
        );

        // set timelock roles
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("PROVIDER_MANAGER_ROLE"), address(timelock)
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("ASSET_MANAGER_ROLE"), address(timelock)
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("BUFFER_MANAGER_ROLE"), address(timelock)
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("PROCESSOR_MANAGER_ROLE"), address(timelock)
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector,
                keccak256("KERNEL_DEPENDENCY_MANAGER_ROLE"),
                address(timelock)
            )
        );

        // set provider
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("PROVIDER_MANAGER_ROLE"), actors.ADMIN()
            )
        );
        addToBatch(address(vault), 0, abi.encodeWithSelector(IVault.setProvider.selector, address(rateProvider)));
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.renounceRole.selector, keccak256("PROVIDER_MANAGER_ROLE"), actors.ADMIN()
            )
        );

        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());

        // add kernel vaults as assets
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("ASSET_MANAGER_ROLE"), actors.ADMIN()
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                KernelStrategy.addAssetWithDecimals.selector, stakerGateway.getVault(contracts.WBNB()), 18, false
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                KernelStrategy.addAssetWithDecimals.selector, stakerGateway.getVault(contracts.SLISBNB()), 18, false
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                KernelStrategy.addAssetWithDecimals.selector, stakerGateway.getVault(contracts.BNBX()), 18, false
            )
        );
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.renounceRole.selector, keccak256("ASSET_MANAGER_ROLE"), actors.ADMIN()
            )
        );

        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.grantRole.selector, keccak256("PROCESSOR_MANAGER_ROLE"), actors.ADMIN()
            )
        );
        // create approval rule
        {
            bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));
            address[] memory allowList = new address[](1);
            allowList[0] = contracts.STAKER_GATEWAY();

            IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

            paramRules[0] =
                IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});
            paramRules[1] =
                IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

            IVault.FunctionRule memory rule =
                IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

            addToBatch(
                address(vault),
                0,
                abi.encodeWithSelector(IVault.setProcessorRule.selector, contracts.SLISBNB(), funcSig, rule)
            );
        }

        // create stakingRule
        {
            address[] memory assets = new address[](1);
            assets[0] = contracts.SLISBNB();
            bytes4 funcSig = bytes4(keccak256("stake(address,uint256,string)"));

            IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

            paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});
            paramRules[1] =
                IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

            paramRules[2] =
                IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

            IVault.FunctionRule memory ruleStaking =
                IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

            addToBatch(
                address(vault),
                0,
                abi.encodeWithSelector(
                    IVault.setProcessorRule.selector, contracts.STAKER_GATEWAY(), funcSig, ruleStaking
                )
            );
        }
        addToBatch(
            address(vault),
            0,
            abi.encodeWithSelector(
                AccessControlUpgradeable.renounceRole.selector, keccak256("PROCESSOR_MANAGER_ROLE"), actors.ADMIN()
            )
        );

        addToBatch(address(vault), 0, abi.encodeWithSelector(IVault.unpause.selector));

        addToBatch(address(vault), 0, abi.encodeWithSelector(IVault.processAccounting.selector));

        Transaction memory batch = getBatch();
        saveTransaction("execute", batch);
    }

    function saveTransaction(string memory key, Transaction memory tx_) public {
        vm.serializeUint(key, "operation", uint256(tx_.operation));
        vm.serializeAddress(key, "to", tx_.to);
        vm.serializeUint(key, "value", tx_.value);
        string memory txJson = vm.serializeBytes(key, "data", tx_.data);

        vm.serializeString(symbol(), key, txJson);
    }
}
