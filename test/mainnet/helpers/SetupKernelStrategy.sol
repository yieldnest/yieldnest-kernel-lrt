// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {SetupVault, Vault, IVault} from "lib/yieldnest-vault/test/mainnet/helpers/SetupVault.sol";
import {TimelockController as TLC} from "lib/yieldnest-vault/src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";
import {MigrateKernelStrategy} from "src/MigrateKernelStrategy.sol";
import {MainnetActors} from "script/Actors.sol";
import {ITransparentUpgradeableProxy, TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Etches} from "lib/yieldnest-vault/test/mainnet/helpers/Etches.sol";

contract SetupKernelStrategy is Test, MainnetActors, Etches {
    Vault public maxVault;
    KernelStrategy public vault;
    KernelStrategy public buffer;

    function deploy() public returns (Vault, KernelStrategy, KernelStrategy) {
        SetupVault setupVault = new SetupVault();
        maxVault = setupVault.deploy();

        // etch to mock ETHRate provider and Buffer
        mockAll();

        buffer = deployBuffer();
        vault = deployMigrateVault();

        // etch buffer to setup buffer for max vault
        // bytes memory code = address(buffer).code;
        // vm.etch(MC.BUFFER, code);

        return (maxVault, vault, buffer);
    }

    function deployBuffer() internal returns (KernelStrategy) {
        // Deploy implementation contract
        KernelStrategy implementation = new KernelStrategy();

        // Deploy transparent proxy
        bytes memory initData = abi.encodeWithSelector(KernelStrategy.initialize.selector, MainnetActors.ADMIN, "ynWBNB Buffer", "ynWBNBk", 18);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(MainnetActors.ADMIN),
            initData
        );

        // Cast proxy to KernelStrategy type
        buffer = KernelStrategy(payable(address(proxy)));

        assertEq(buffer.symbol(), "ynWBNBk");

        configureBuffer(buffer);

        return buffer;
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
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), address(maxVault));

        // set strategy manager to admin for now
        vault_.grantRole(vault_.STRATEGY_MANAGER_ROLE(), address(ADMIN));

        vault_.setProvider(MC.PROVIDER);

        vault_.setStakerGateway(MC.STAKER_GATEWAY);

        vault_.setSyncDeposit(true);

        vault_.addAsset(MC.WBNB, 18, true);

        // set deposit rules
        setDepositRule(vault_, MC.WBNB, address(vault_));

        // set approval rules
        setApprovalRule(vault_, address(vault_), MC.STAKER_GATEWAY);

        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
    }


    function deployMigrateVault() internal returns (KernelStrategy) {
        MigrateKernelStrategy migrationVault = MigrateKernelStrategy(payable(MC.YNBNBk));

        uint256 previousTotalAssets = migrationVault.totalAssets();

        uint256 previousTotalSupply = migrationVault.totalSupply();

        address specificHolder = 0xCfac0990700eD9B67FeFBD4b26a79E426468a419;

        uint256 previousBalance = migrationVault.balanceOf(specificHolder);

        MigrateKernelStrategy implemention = new MigrateKernelStrategy();

        // TODO: move admin to actors
        vm.prank(0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a);
        ProxyAdmin proxyAdmin = ProxyAdmin(MC.YNBNBk_PROXY_ADMIN);

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(MC.YNBNBk),
            address(implemention),
            abi.encodeWithSelector(
                MigrateKernelStrategy.initializeAndMigrate.selector,
                address(MainnetActors.ADMIN),
                "YieldNest BNB Kernel",
                "ynBNBk",
                18
            )
        );

        uint256 newTotalAssets = migrationVault.totalAssets();
        assertEq(newTotalAssets, previousTotalAssets, "Total assets should remain the same after upgrade");

        uint256 newTotalSupply = migrationVault.totalSupply();
        assertEq(newTotalSupply, previousTotalSupply, "Total supply should remain the same after upgrade");

        uint256 newBalance = migrationVault.balanceOf(specificHolder);
        assertEq(newBalance, previousBalance, "Balance should remain the same after upgrade");

        vault = KernelStrategy(payable(address(migrationVault)));
        configureMigrationVault(vault);

        return vault;
    }

    function configureMigrationVault(KernelStrategy vault_) internal {
        vm.startPrank(ADMIN);

        vault_.grantRole(vault_.PROCESSOR_ROLE(), PROCESSOR);
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault_.grantRole(vault_.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault_.grantRole(vault_.PAUSER_ROLE(), PAUSER);
        vault_.grantRole(vault_.UNPAUSER_ROLE(), UNPAUSER);
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), address(maxVault));

        // set strategy manager to admin for now
        vault_.grantRole(vault_.STRATEGY_MANAGER_ROLE(), address(ADMIN));

        vault_.setProvider(MC.PROVIDER);

        vault_.setStakerGateway(MC.STAKER_GATEWAY);

        // set deposit rules
        setDepositRule(vault_, MC.SLISBNB, address(vault_));

        // set staking rule
        setStakingRule(vault_, MC.SLISBNB);

        // set approval rules
        setApprovalRule(vault_, address(vault_), MC.STAKER_GATEWAY);

        vault_.unpause();

        vm.stopPrank();

        vault.processAccounting();
    }

    function setDepositRule(KernelStrategy vault_, address contractAddress, address receiver) public {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setStakingRule(KernelStrategy vault_, address asset) public {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        setStakingRule(vault_, assets);
    }

    function setStakingRule(KernelStrategy vault_, address[] memory assets) public {
        bytes4 funcSig = bytes4(keccak256("stake(address,uint256,string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // since there is no verification for uints in the Guard.sol, setting the string param to uint256
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});
        vault_.setProcessorRule(MC.STAKER_GATEWAY, funcSig, rule);
    }

    function setApprovalRule(KernelStrategy vault_, address contractAddress, address spender) public {
        address[] memory allowList = new address[](1);
        allowList[0] = spender;
        setApprovalRule(vault_, contractAddress, allowList);
    }

    function setApprovalRule(KernelStrategy vault_, address contractAddress, address[] memory allowList) public {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }
}
