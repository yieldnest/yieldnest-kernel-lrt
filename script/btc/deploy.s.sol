// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Vault} from "lib/yieldnest-vault/src/Vault.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {BTCRateProvider} from "src/module/BTCRateProvider.sol";
import {TestnetBTCRateProvider} from "test/module/BTCRateProvider.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {FeeMath} from "lib/yieldnest-vault/src/module/FeeMath.sol";
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

        _renounceTemporaryRoles(vault_);
    }
}
