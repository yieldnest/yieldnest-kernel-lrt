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

// FOUNDRY_PROFILE=mainnet forge script DeployYnCoBTCkStrategy --sender 0xa1E340bd1e3ea09B3981164BBB4AfeDdF0e7bA0D
// --account [accountname]
contract DeployYnBTCkStrategy is BaseKernelScript {
    function symbol() public pure override returns (string memory) {
        return "ynBTCk";
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
        string memory name = "YieldNest Restaked BTC - Kernel";
        string memory symbol_ = "ynBTCk";
        uint8 decimals = 18;

        uint64 baseWithdrawalFee = uint64(0.001 ether * FeeMath.BASIS_POINT_SCALE / 1 ether); // 0.1%
        bool countNativeAsset = false;
        bool alwaysComputeTotalAssets = true;
        bytes memory initData = abi.encodeWithSelector(
            Vault.initialize.selector,
            admin,
            name,
            symbol_,
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

        vault_.addAsset(contracts.BTCB(), true);
        vault_.addAsset(contracts.SOLVBTC(), true);
        vault_.addAsset(contracts.SOLVBTC_BBN(), true);

        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.BTCB()), 18, false);
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.SOLVBTC()), 18, false);
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.SOLVBTC_BBN()), 18, false);

        setApprovalRule(vault_, contracts.BTCB(), contracts.STAKER_GATEWAY());
        setApprovalRule(vault_, contracts.SOLVBTC(), contracts.STAKER_GATEWAY());
        setApprovalRule(vault_, contracts.SOLVBTC_BBN(), contracts.STAKER_GATEWAY());

        address[] memory assets = new address[](3);
        assets[0] = contracts.BTCB();
        assets[1] = contracts.SOLVBTC();
        assets[2] = contracts.SOLVBTC_BBN();
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), assets);
        setUnstakingRule(vault_, contracts.STAKER_GATEWAY(), assets);

        vault_.unpause();

        vault_.processAccounting();

        _renounceTemporaryRoles();
    }
}
