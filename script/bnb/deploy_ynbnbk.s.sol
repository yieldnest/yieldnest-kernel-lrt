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
// import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {
    ITransparentUpgradeableProxy,
    ProxyAdmin
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import {BaseScript} from "script/BaseScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployYnBNBkStrategy --sig "run(bool)" <true/false> --sender
// 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract DeployYnBNBkStrategy is BaseScript {
    struct Transaction {
        address target;
        uint256 value;
        bytes data;
    }

    Transaction[] public transactions;

    error InvalidSender();

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

    function runWithOption(bool createMultiSigTx) public {
        _setup();
        // TODO: do not deploy a new timelock controller if one already exists
        _deployTimelockController();
        deployRateProvider();

        _verifySetup();

        deployMigrateVault(createMultiSigTx);

        _saveDeployment();

        vm.stopBroadcast();
    }

    function deployMigrateVault(bool createMultiSigTx) internal returns (KernelStrategy) {
        implementation = KernelStrategy(payable(address(new MigratedKernelStrategy())));

        address vaultAddress = contracts.YNBNBK();

        ProxyAdmin proxyAdmin = ProxyAdmin(ProxyUtils.getProxyAdmin(vaultAddress));

        MigratedKernelStrategy.Asset[] memory assets = new MigratedKernelStrategy.Asset[](3);

        assets[0] = MigratedKernelStrategy.Asset({asset: contracts.WBNB(), active: false});
        assets[1] = MigratedKernelStrategy.Asset({asset: contracts.SLISBNB(), active: true});
        assets[2] = MigratedKernelStrategy.Asset({asset: contracts.BNBX(), active: true});

        // TODO: handle if proxy admin owner is a time lock controller
        if (createMultiSigTx) {
            // create upgrade call transaction
            bytes memory upgradeData = abi.encodeWithSelector(
                proxyAdmin.upgradeAndCall.selector,
                abi.encode(
                    ITransparentUpgradeableProxy(vaultAddress),
                    implementation,
                    abi.encodeWithSelector(
                        MigratedKernelStrategy.initializeAndMigrate.selector,
                        msg.sender,
                        "YieldNest Restaked BNB - Kernel",
                        symbol(),
                        18,
                        assets,
                        contracts.STAKER_GATEWAY(),
                        false,
                        true,
                        0,
                        true
                    )
                )
            );

            Transaction memory tx = Transaction({target: address(proxyAdmin), value: 0, data: upgradeData});
            transactions.push(tx);

            createConfigureVaultTransactions(address(proxyAdmin));

            return KernelStrategy(payable(address(vaultAddress)));
        } else {
            if (proxyAdmin.owner() != msg.sender) {
                revert InvalidSender();
            }

            proxyAdmin.upgradeAndCall(
                ITransparentUpgradeableProxy(vaultAddress),
                address(implementation),
                abi.encodeWithSelector(
                    MigratedKernelStrategy.initializeAndMigrate.selector,
                    msg.sender,
                    "YieldNest Restaked BNB - Kernel",
                    symbol(),
                    18,
                    assets,
                    contracts.STAKER_GATEWAY(),
                    false,
                    true,
                    0,
                    true
                )
            );

            vault = KernelStrategy(payable(address(vaultAddress)));
            configureVault(vault);

            return vault;
        }
    }

    function configureVault(KernelStrategy vault_) internal {
        _configureDefaultRoles(vault_);
        _configureTemporaryRoles(vault_);

        // set provider
        vault_.setProvider(address(rateProvider));

        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());

        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.WBNB()), 18, false);
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.SLISBNB()), 18, false);
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.BNBX()), 18, false);

        setApprovalRule(vault_, contracts.SLISBNB(), contracts.STAKER_GATEWAY());
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.SLISBNB());

        vault_.unpause();

        vault_.processAccounting();

        _renounceTemporaryRoles(vault_);
    }

    function createConfigureVaultTransactions(address vaultAddress) internal {
        // TODO: fix these transactions to mirror `configureVault` above, particularly fix timelock
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector, keccak256("DEFAULT_ADMIN_ROLE"), actors.ADMIN()
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector, keccak256("PROCESSOR_ROLE"), actors.ADMIN()
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector,
                    keccak256("PROVIDER_MANAGER_ROLE"),
                    actors.PROVIDER_MANAGER()
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector, keccak256("ASSET_MANAGER_ROLE"), actors.ASSET_MANAGER()
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector, keccak256("BUFFER_MANAGER_ROLE"), actors.BUFFER_MANAGER()
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector,
                    keccak256("PROCESSOR_MANAGER_ROLE"),
                    actors.PROCESSOR_MANAGER()
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector, keccak256("PAUSER_ROLE"), actors.PAUSER()
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector, keccak256("UNPAUSER_ROLE"), actors.UNPAUSER()
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector, keccak256("PROCESSOR_MANAGER_ROLE"), msg.sender
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector, keccak256("PROVIDER_MANAGER_ROLE"), msg.sender
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector, keccak256("ASSET_MANAGER_ROLE"), msg.sender
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.grantRole.selector, keccak256("UNPAUSER_ROLE"), msg.sender
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(IVault.setProvider.selector, address(rateProvider))
            })
        );
        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    KernelStrategy.addAssetWithDecimals.selector, stakerGateway.getVault(contracts.WBNB()), 18, false
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    KernelStrategy.addAssetWithDecimals.selector, stakerGateway.getVault(contracts.SLISBNB()), 18, false
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    KernelStrategy.addAssetWithDecimals.selector, stakerGateway.getVault(contracts.BNBX()), 18, false
                )
            })
        );

        // create approval rule
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));
        address[] memory allowList = new address[](1);
        allowList[0] = contracts.STAKER_GATEWAY();

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(IVault.setProcessorRule.selector, contracts.SLISBNB(), funcSig, rule)
            })
        );

        // create stakingRule
        address[] memory assets = new address[](1);
        assets[0] = contracts.SLISBNB();
        bytes4 funcSigStaking = bytes4(keccak256("stake(address,uint256,string)"));

        IVault.ParamRule[] memory paramRulesStaking = new IVault.ParamRule[](3);

        paramRulesStaking[0] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});
        paramRulesStaking[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRulesStaking[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory ruleStaking =
            IVault.FunctionRule({isActive: true, paramRules: paramRulesStaking, validator: IValidator(address(0))});

        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    IVault.setProcessorRule.selector, contracts.STAKER_GATEWAY(), funcSigStaking, ruleStaking
                )
            })
        );
        transactions.push(
            Transaction({target: vaultAddress, value: 0, data: abi.encodeWithSelector(IVault.unpause.selector)})
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(IVault.processAccounting.selector)
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.renounceRole.selector, keccak256("DEFAULT_ADMIN_ROLE"), msg.sender
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.renounceRole.selector, keccak256("PROCESSOR_MANAGER_ROLE"), msg.sender
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.renounceRole.selector, keccak256("PROVIDER_MANAGER_ROLE"), msg.sender
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.renounceRole.selector, keccak256("ASSET_MANAGER_ROLE"), msg.sender
                )
            })
        );
        transactions.push(
            Transaction({
                target: vaultAddress,
                value: 0,
                data: abi.encodeWithSelector(
                    AccessControlUpgradeable.renounceRole.selector, keccak256("UNPAUSER_ROLE"), msg.sender
                )
            })
        );
    }

    // TODO: move this to a library or base script file and use it everywhere as required
    function saveDeployment() public {
        if (transactions.length > 0) {
            vm.serializeAddress(symbol(), "deployer", msg.sender);
            vm.serializeAddress(symbol(), string.concat(symbol(), "-proxy"), address(vault));
            vm.serializeAddress(symbol(), "rateProvider", address(rateProvider));
            vm.serializeAddress(symbol(), string.concat(symbol(), "-implementation"), address(implementation));

            address[] memory targets = new address[](transactions.length);
            uint256[] memory values = new uint256[](transactions.length);
            bytes[] memory datas = new bytes[](transactions.length);
            string[] memory txs = new string[](transactions.length);
            for (uint256 i = 0; i < transactions.length; i++) {
                targets[i] = transactions[i].target;
                values[i] = transactions[i].value;
                datas[i] = transactions[i].data;

                vm.serializeAddress(string(abi.encodePacked(i)), "target", transactions[i].target);
                vm.serializeUint(string(abi.encodePacked(i)), "value", transactions[i].value);
                string memory temp = vm.serializeBytes(string(abi.encodePacked(i)), "data", transactions[i].data);

                txs[i] = temp;
            }
            string memory jsonOutput = vm.serializeString(symbol(), "transactions", txs);
            vm.writeJson(
                jsonOutput, string.concat("./deployments/", symbol(), "-", Strings.toString(block.chainid), ".json")
            );
        } else {
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
}
