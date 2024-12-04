// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {KernelRateProvider} from "src/module/KernelRateProvider.sol";
import {SetupVault, Vault, IVault} from "lib/yieldnest-vault/test/unit/helpers/SetupVault.sol";
import {TimelockController as TLC} from "lib/yieldnest-vault/src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";
import {MigratedKernelStrategy} from "src/MigratedKernelStrategy.sol";
import {MainnetActors} from "script/Actors.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {EtchUtils} from "test/unit/helpers/EtchUtils.sol";
import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";

contract SetupKernelStrategy is Test, AssertUtils, MainnetActors, EtchUtils {
    KernelStrategy public vault;
    WETH9 public weth;
    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function deploy() public {
        mockAll();

        KernelStrategy implementation = new KernelStrategy();
        bytes memory initData = abi.encodeWithSelector(
            KernelStrategy.initialize.selector, MainnetActors.ADMIN, "YieldNest Restaked BNB - Kernel", "ynWBNBk", 18
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(MainnetActors.ADMIN), initData);

        vault = KernelStrategy(payable(address(proxy)));

        weth = WETH9(payable(MC.WETH));

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

        // since we're not testing the max vault, we'll set the admin as the allocator role
        vault.grantRole(vault.ALLOCATOR_ROLE(), address(ADMIN));

        // set strategy manager to admin for now
        vault.grantRole(vault.STRATEGY_MANAGER_ROLE(), address(ADMIN));

        // set provider
        vault.setProvider(MC.PROVIDER);

        // set staker gateway
        vault.setStakerGateway(MC.STAKER_GATEWAY);

        // by default, we don't sync deposits or withdraws
        // we set it for individual tests
        // vault.setSyncDeposit(true);
        // vault.setSyncWithdraw(true);

        // add assets
        vault.addAsset(MC.WBNB, 18, true);
        vault.addAsset(MC.SLISBNB, 18, true);
        vault.addAsset(MC.BNBX, 18, true);

        // by default, we don't set any rules
        // set deposit rules
        // setDepositRule(MC.WBNB, address(vault));

        // set approval rules
        // setApprovalRule(address(vault), MC.STAKER_GATEWAY);

        vault.unpause();

        vm.stopPrank();

        vault.processAccounting();
    }

    function setDepositRule(address contractAddress, address receiver) public {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setStakingRule(address asset) public {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        setStakingRule(assets);
    }

    function setStakingRule(address[] memory assets) public {
        bytes4 funcSig = bytes4(keccak256("stake(address,uint256,string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // since there is no verification for uints in the Guard.sol, setting the string param to uint256
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});
        vault.setProcessorRule(MC.STAKER_GATEWAY, funcSig, rule);
    }

    function setApprovalRule(address contractAddress, address spender) public {
        address[] memory allowList = new address[](1);
        allowList[0] = spender;
        setApprovalRule(contractAddress, allowList);
    }

    function setApprovalRule(address contractAddress, address[] memory allowList) public {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault.setProcessorRule(contractAddress, funcSig, rule);
    }
}
