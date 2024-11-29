// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {SetupVault, Vault, IVault} from "lib/yieldnest-vault/test/mainnet/helpers/SetupVault.sol";
import {TimelockController as TLC} from "src/Common.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";
import {MigrateKernelStrategy} from "src/MigrateKernelStrategy.sol";
import {MainnetActors} from "script/Actors.sol";
import {ITransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Etches} from "test/mainnet/helpers/Etches.sol";

contract SetupKernelStrategy is Test, MainnetActors, Etches {

    function upgrade() public returns (KernelStrategy) {
     SetupVault setupVault = new SetupVault();
        maxVault = setupVault.deploy();

        vault = MigrateKernelStrategy(payable(MC.YNBNBk));

        uint256 previousTotalAssets = vault.totalAssets();

        uint256 previousTotalSupply = vault.totalSupply();

        address specificHolder = 0xCfac0990700eD9B67FeFBD4b26a79E426468a419;

        uint256 previousBalance = vault.balanceOf(specificHolder);

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


        uint256 newTotalAssets = vault.totalAssets();
        assertEq(newTotalAssets, previousTotalAssets, "Total assets should remain the same after upgrade");

        uint256 newTotalSupply = vault.totalSupply();
        assertEq(newTotalSupply, previousTotalSupply, "Total supply should remain the same after upgrade");

        uint256 newBalance = vault.balanceOf(specificHolder);
        assertEq(newBalance, previousBalance, "Balance should remain the same after upgrade");

        configureVault();

        return vault;
    }

    function configureVault() internal {

        // etch to mock ETHRate provider and Buffer
        mockAll();

        vm.startPrank(ADMIN);
        
        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.ALLOCATOR_ROLE(), address(maxVault));

        vault.setProvider(MC.PROVIDER);

        vault.setStakerGateway(MC.STAKER_GATEWAY);

        // set deposit rules
        setDepositRule(vault, MC.SLISBNB, address(vault));

        // set staking rule
        address[] memory stakableAssets = new address[](1);
        stakableAssets[0] = MC.SLISBNB;
        setStakingRule(vault, stakableAssets);
        
        // set approval rules
        setApprovalRule(vault, address(vault), MC.YNBNBk);
        setApprovalRule(vault, address(vault), MC.STAKER_GATEWAY);

        vault.unpause();

        vm.stopPrank();

        vault.processAccounting();
    }

    function setDepositRule(Vault vault_, address contractAddress, address receiver) public {
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

    function setStakingRule(Vault vault_, address[] memory assets) public {
        bytes4 funcSig = bytes4(keccack256("stake(address,uint256,string)"));

        IVault.ParamRule[] memory paramRules = new IVaultParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets });
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // since there is no verification for uints in the Guard.sol, setting the string param to uint256
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});
         vault_.setProcessorRule(MC.STAKER_GATEWAY, funcSig, rule);
    }

    function setApprovalRule(Vault vault_, address contractAddress, address spender) public {
        address[] memory allowList = new address[](1);
        allowList[0] = spender;
        setApprovalRule(vault_, contractAddress, allowList);
    }

    function setApprovalRule(Vault vault_, address contractAddress, address[] memory allowList) public {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }
 
}