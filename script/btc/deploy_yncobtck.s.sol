// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider, Vault} from "lib/yieldnest-vault/script/BaseScript.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {BTCRateProvider} from "src/module/BTCRateProvider.sol";
import {TestnetBTCRateProvider} from "test/module/BTCRateProvider.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {FeeMath} from "lib/yieldnest-vault/src/module/FeeMath.sol";
import {BaseKernelScript} from "script/BaseKernelScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployYnCoBTCktrategy --sender 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract DeployYnCoBTCkStrategy is BaseKernelScript {
    function symbol() public pure override returns (string memory) {
        return "ynCoBTCk";
    }

    function deployRateProvider() internal {
        if (block.chainid == 97) {
            rateProvider = IProvider(address(new TestnetBTCRateProvider()));
        }

        if (block.chainid == 56) {
            rateProvider = IProvider(address(new BTCRateProvider()));
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
        implementation = Vault(payable(address(new KernelStrategy())));

        address admin = msg.sender;
        string memory name = "YieldNest Restaked Coffer BTC - Kernel";
        uint8 decimals = 18;

        uint64 baseWithdrawalFee = uint64(0.001 ether * FeeMath.BASIS_POINT_SCALE / 1 ether); // 0.1%
        bool countNativeAsset = false;
        bool alwaysComputeTotalAssets = true;
        bytes memory initData = abi.encodeWithSelector(
            Vault.initialize.selector,
            admin,
            name,
            symbol(),
            decimals,
            baseWithdrawalFee,
            countNativeAsset,
            alwaysComputeTotalAssets
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(timelock), initData);

        vault = Vault(payable(address(proxy)));

        configureVault();
    }

    function configureVault() internal {
        _configureDefaultRoles();
        _configureTemporaryRoles();

        // set provider
        vault_.setStakerGateway(contracts.STAKER_GATEWAY());
        vault_.setProvider(address(rateProvider));
        vault_.setSyncDeposit(true);
        vault_.setSyncWithdraw(true);

        vault_.addAsset(contracts.COBTC(), true);
        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());
        // VERY IMPORTANT: COBTC has 8 decimals
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.COBTC()), 8, false);

        setApprovalRule(vault_, contracts.COBTC(), contracts.STAKER_GATEWAY());

        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.COBTC());
        setUnstakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.COBTC());

        vault_.unpause();

        // No need to call processAccounting here, since alwaysComputeTotalAssets is true
        // vault_.processAccounting();

        _renounceTemporaryRoles();
    }
}
