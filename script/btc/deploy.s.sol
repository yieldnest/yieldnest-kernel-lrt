// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {BTCRateProvider, TestnetBTCRateProvider} from "src/module/BTCRateProvider.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {BaseScript} from "script/BaseScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployYnBTCkStrategy --sender 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract DeployYnBTCkStrategy is BaseScript {
    function symbol() public pure override returns (string memory) {
        return "ynBTCk";
    }

    function deployRateProvider() internal {
        if (block.chainid == 97) {
            rateProvider = IProvider(new TestnetBTCRateProvider());
        }

        if (block.chainid == 56) {
            rateProvider = IProvider(new BTCRateProvider());
        }
    }

    function run() public {
        vm.startBroadcast();

        _setup();
        _deployTimelockController();
        deployRateProvider();

        _verifySetup();

        deploy();

        _deployViewer();

        _saveDeployment();

        vm.stopBroadcast();
    }

    function deploy() internal {
        implementation = new KernelStrategy();

        bytes memory initData = abi.encodeWithSelector(
            KernelStrategy.initialize.selector, msg.sender, "YieldNest Restaked BTC - Kernel", "ynBTCk", 18, 0, false
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(actors.ADMIN()), initData);

        vault = KernelStrategy(payable(address(proxy)));

        configureVault(vault);
    }

    function configureVault(KernelStrategy vault_) internal {
        _configureDefaultRoles(vault_);
        _configureTemporaryRoles(vault_);

        // set provider
        vault_.setStakerGateway(contracts.STAKER_GATEWAY());
        vault_.setProvider(address(rateProvider));
        vault_.setHasAllocator(false);
        vault_.setSyncDeposit(true);
        vault_.setSyncWithdraw(true);

        vault_.addAsset(contracts.BTCB(), true);
        vault_.addAsset(contracts.SOLVBTC(), true);
        vault_.addAsset(contracts.SOLVBTC_BNN(), true);

        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.BTCB()), 18, false);
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.SOLVBTC()), 18, false);
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.SOLVBTC_BNN()), 18, false);

        setApprovalRule(vault_, contracts.BTCB(), contracts.STAKER_GATEWAY());
        setApprovalRule(vault_, contracts.SOLVBTC(), contracts.STAKER_GATEWAY());
        setApprovalRule(vault_, contracts.SOLVBTC_BNN(), contracts.STAKER_GATEWAY());

        address[] memory assets = new address[](3);
        assets[0] = contracts.BTCB();
        assets[1] = contracts.SOLVBTC();
        assets[2] = contracts.SOLVBTC_BNN();
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), assets);

        vault_.unpause();

        vault_.processAccounting();

        _renounceTemporaryRoles(vault_);
    }
}
