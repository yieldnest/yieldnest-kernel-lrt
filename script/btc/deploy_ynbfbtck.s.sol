// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider, Vault} from "lib/yieldnest-vault/script/BaseScript.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {BfBTCRateProvider} from "src/module/BfBTCRateProvider.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {console} from "lib/forge-std/src/console.sol";
import {BaseKernelScript} from "script/BaseKernelScript.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployYnBfBTCkStrategy --sender 0xa1E340bd1e3ea09B3981164BBB4AfeDdF0e7bA0D
// --account [accountname]
contract DeployYnBfBTCkStrategy is BaseKernelScript {
    function symbol() public pure override returns (string memory) {
        return "ynBfBTCk";
    }

    function deployRateProvider() internal {
        if (block.chainid == 56) {
            rateProvider = IProvider(address(new BfBTCRateProvider()));
            return;
        }
        // only bsc mainnet is supported for ynBfBTCk
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

        string memory name = "YieldNest Restaked BitFi BTC - Kernel";
        uint8 decimals = 8;

        console.log("Deploying YieldNest Restaked BitFi BTC - Kernel (ynBfBTCk) by", msg.sender);

        uint64 baseWithdrawalFee = 0;
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

        // set as false now, since kernel doesn't support it yet
        // vault_.setSyncDeposit(false);
        // vault_.setSyncWithdraw(false);
        // vault_.setHasAllocator(false);

        // Adding the BFBTC asset to the vault with 8 decimals, and setting it as both depositable and withdrawable
        vault_.addAssetWithDecimals(contracts.BFBTC(), 8, true, true);

        // not adding the kernel vault and rules now, since kernel doesn't support it yet
        // IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());
        // // VERY IMPORTANT: BFBTC has 8 decimals
        // vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.BFBTC()), 8, false);
        //
        // setApprovalRule(vault_, contracts.BFBTC(), contracts.STAKER_GATEWAY());
        //
        // setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.BFBTC());
        // setUnstakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.BFBTC());

        vault_.unpause();

        // No need to call processAccounting here, since alwaysComputeTotalAssets is true
        // vault_.processAccounting();

        _renounceTemporaryRoles();
    }
}
