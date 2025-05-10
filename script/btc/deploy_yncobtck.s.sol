// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider, Vault} from "lib/yieldnest-vault/script/BaseScript.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {CoBTCRateProvider} from "src/module/CoBTCRateProvider.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {console} from "lib/forge-std/src/console.sol";
import {BaseKernelScript} from "script/BaseKernelScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployYnCoBTCkStrategy --sender 0xa1E340bd1e3ea09B3981164BBB4AfeDdF0e7bA0D
// --account [accountname]
contract DeployYnCoBTCkStrategy is BaseKernelScript {
    function symbol() public pure override returns (string memory) {
        return "ynCoBTCk";
    }

    function deployRateProvider() internal {
        if (block.chainid == 56) {
            rateProvider = IProvider(address(new CoBTCRateProvider()));
            return;
        }
        // only bsc mainnet is supported for ynCoBTCk
        revert UnsupportedChain();
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
        uint8 decimals = 8;

        console.log("Deploying YieldNest Restaked Coffer BTC - Kernel (ynCoBTCk) by", msg.sender);

        uint64 baseWithdrawalFee = 0; // 0%
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

        // Adding the COBTC asset to the vault with 8 decimals, and setting it as both depositable and withdrawable
        vault_.addAssetWithDecimals(contracts.COBTC(), 8, true, true);

        // Getting the staker gateway instance
        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());

        // Adding the staker gateway's vault for COBTC to the vault with 8 decimals
        // but setting it as neither depositable nor withdrawable
        // VERY IMPORTANT: COBTC has 8 decimals
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.COBTC()), 8, false, false);

        setApprovalRule(vault_, contracts.COBTC(), contracts.STAKER_GATEWAY());

        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.COBTC());
        setUnstakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.COBTC());

        vault_.unpause();

        // No need to call processAccounting here, since alwaysComputeTotalAssets is true
        // vault_.processAccounting();

        _renounceTemporaryRoles();
    }
}
