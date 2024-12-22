// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider, Vault} from "lib/yieldnest-vault/script/BaseScript.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {BNBRateProvider} from "src/module/BNBRateProvider.sol";
import {TestnetBNBRateProvider} from "test/module/BNBRateProvider.sol";

import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseKernelScript} from "script/BaseKernelScript.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployYnWBNBkStrategy --sender 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract DeployYnWBNBkStrategy is BaseKernelScript {
    function symbol() public pure override returns (string memory) {
        return "ynWBNBk";
    }

    function deployRateProvider() internal {
        if (block.chainid == 97) {
            rateProvider = IProvider(address(new TestnetBNBRateProvider()));
        }

        if (block.chainid == 56) {
            rateProvider = IProvider(address(new BNBRateProvider()));
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
        string memory name = "YieldNest WBNB Buffer - Kernel";
        string memory symbol_ = "ynWBNBk";
        uint8 decimals = 18;
        uint64 baseWithdrawalFee = 0;
        bool countNativeAsset = true;
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
            new TransparentUpgradeableProxy(address(implementation), address(actors_.ADMIN()), initData);

        vault = Vault(payable(address(proxy)));

        configureVault();
    }

    function configureVault() internal {
        _configureDefaultRoles();
        _configureTemporaryRoles();

        // set allocator to ynbnbx
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), contracts.YNBNBX());

        vault_.setProvider(address(rateProvider));
        vault_.setHasAllocator(true);
        vault_.setStakerGateway(contracts.STAKER_GATEWAY());
        vault_.setSyncDeposit(true);
        vault_.setSyncWithdraw(true);

        vault_.addAsset(contracts.WBNB(), true);
        vault_.addAssetWithDecimals(IStakerGateway(contracts.STAKER_GATEWAY()).getVault(contracts.WBNB()), 18, false);

        setApprovalRule(vault_, contracts.WBNB(), contracts.STAKER_GATEWAY());
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.WBNB());
        setUnstakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.WBNB());

        vault_.unpause();

        vault_.processAccounting();

        _renounceTemporaryRoles();
    }
}
