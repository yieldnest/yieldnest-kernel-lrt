// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider, Vault} from "lib/yieldnest-vault/script/BaseScript.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {BNBRateProvider} from "src/module/BNBRateProvider.sol";
import {TestnetBNBRateProvider} from "test/module/BNBRateProvider.sol";

import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {console} from "lib/forge-std/src/console.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseKernelScript} from "script/BaseKernelScript.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployYnWBNBkStrategy --sender 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract DeployYnAsBNBkStrategy is BaseKernelScript {
    function symbol() public pure override returns (string memory) {
        return "ynAsBNBk";
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
        string memory name = "YieldNest AsBNB Buffer - Kernel";
        string memory symbol_ = "ynAsBNBk";
        uint8 decimals = 18;
        uint64 baseWithdrawalFee = 0;
        bool countNativeAsset = true;
        bool alwaysComputeTotalAssets = true;
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(timelock), "");

        vault = Vault(payable(address(proxy)));

        vault.initialize(admin, name, symbol_, decimals, baseWithdrawalFee, countNativeAsset, alwaysComputeTotalAssets);

        configureVault();
    }

    function configureVault() internal {
        _configureDefaultRoles();
        _configureTemporaryRoles();

        console.log("ASBNB address:", contracts.ASBNB());

        // set allocator to ynbnbx
        if (contracts.ASBNB() != address(0)) {
            // TODO: set allocator correct allocator might need an slisBnB vault
            vault_.grantRole(vault_.ALLOCATOR_ROLE(), contracts.YNBNBX());
        } else {
            console.log("ASBNB is still undefined (zero address)");
        }

        vault_.setProvider(address(rateProvider));
        vault_.setHasAllocator(true);
        vault_.setStakerGateway(contracts.STAKER_GATEWAY());
        vault_.setSyncDeposit(true);
        vault_.setSyncWithdraw(true);

        vault_.addAsset(contracts.WBNB(), true);
        vault_.addAssetWithDecimals(IStakerGateway(contracts.STAKER_GATEWAY()).getVault(contracts.ASBNB()), 18, true);

        setApprovalRule(vault_, contracts.WBNB(), contracts.STAKER_GATEWAY());
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.ASBNB());
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.WBNB());
        setUnstakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.ASBNB());

        // wbnb
        setWethDepositRule(vault, contracts.WBNB());
        setWethDepositRule(vault, contracts.ASBNB());
        setWethWithdrawRule(vault, contracts.WBNB());
        setWithdrawAssetRule(vault, contracts.STAKER_GATEWAY(), contracts.ASBNB());

        vault_.unpause();

        vault_.processAccounting();

        if (contracts.YNBNBX() == address(0)) {
            vault.renounceRole(vault.PROCESSOR_MANAGER_ROLE(), msg.sender);
            vault.renounceRole(vault.BUFFER_MANAGER_ROLE(), msg.sender);
            vault.renounceRole(vault.PROVIDER_MANAGER_ROLE(), msg.sender);
            vault.renounceRole(vault.ASSET_MANAGER_ROLE(), msg.sender);
            vault.renounceRole(vault.UNPAUSER_ROLE(), msg.sender);

            vault.renounceRole(vault_.KERNEL_DEPENDENCY_MANAGER_ROLE(), msg.sender);
            vault.renounceRole(vault_.DEPOSIT_MANAGER_ROLE(), msg.sender);
            vault.renounceRole(vault_.ALLOCATOR_MANAGER_ROLE(), msg.sender);
            console.log("YNBNBX is still undefined (zero address). Run configure allocator script after deployment.");
        } else {
            _renounceTemporaryRoles();
        }
    }
}
