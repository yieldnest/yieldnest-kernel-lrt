// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";

import {MockSTETH} from "lib/yieldnest-vault/test/unit/mocks/MockST_ETH.sol";
import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {KernelRateProvider} from "src/module/KernelRateProvider.sol";

import {MockStakerGateway} from "../mocks/MockStakerGateway.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {EtchUtils} from "test/unit/helpers/EtchUtils.sol";

contract SetupKernelStrategy is Test, AssertUtils, MainnetActors, EtchUtils {
    KernelStrategy public vault;
    KernelRateProvider public provider;

    WETH9 public wbnb;
    MockSTETH public slisbnb;
    WETH9 public bnbx;

    IStakerGateway public mockGateway;

    address public alice = address(0xa11ce);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function deploy() public {
        mockAll();
        provider = new KernelRateProvider();
        KernelStrategy implementation = new KernelStrategy();
        bytes memory initData = abi.encodeWithSelector(
            KernelStrategy.initialize.selector, MainnetActors.ADMIN, "YieldNest Restaked BNB - Kernel", "ynWBNBk", 18
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(MainnetActors.ADMIN), initData);

        vault = KernelStrategy(payable(address(proxy)));

        wbnb = WETH9(payable(MC.WBNB));
        slisbnb = MockSTETH(payable(MC.SLISBNB));
        bnbx = WETH9(payable(MC.BNBX));

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

        // set strategy manager to admin for now
        vault.grantRole(vault.STRATEGY_MANAGER_ROLE(), address(ADMIN));

        // set provider
        vault.setProvider(address(provider));

        // set staker gateway
        vault.setStakerGateway(address(mockGateway));

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
        // setApprovalRule(address(vault), address(mockGateway));

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
        vault.setProcessorRule(address(mockGateway), funcSig, rule);
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

    function setUnstakingRule(KernelStrategy vault_, address asset) public {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        setUnstakingRule(vault_, assets);
    }

    function setUnstakingRule(KernelStrategy vault_, address[] memory assets) public {
        bytes4 funcSig = bytes4(keccak256("unstake(address,uint256,string)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // since there is no verification for uints in the Guard.sol, setting the string param to uint256
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});
        vault_.setProcessorRule(address(mockGateway), funcSig, rule);
    }
}