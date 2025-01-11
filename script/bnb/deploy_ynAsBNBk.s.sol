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
        if (contracts.ASBNB() == address(0)) {
            revert InvalidSetup();
        }

        implementation = Vault(payable(address(new KernelStrategy())));

        address admin = msg.sender;
        string memory name = "YieldNest Restaked asBNB - Kernel";
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

        vault_.grantRole(vault_.ALLOCATOR_ROLE(), contracts.YNBNBX());
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), actors.BOOTSTRAPPER());
        
        vault_.setProvider(address(rateProvider));
        vault_.setHasAllocator(true);
        vault_.setStakerGateway(contracts.STAKER_GATEWAY());
        vault_.setSyncDeposit(true);
        vault_.setSyncWithdraw(true);

        vault_.addAsset(contracts.WBNB(), false);
        vault_.addAsset(contracts.SLISBNB(), false);
        vault_.addAsset(contracts.ASBNB(), true);

        address asbnbKernelVault = IStakerGateway(contracts.STAKER_GATEWAY()).getVault(contracts.ASBNB());
        vault_.addAssetWithDecimals(asbnbKernelVault, 18, false);

        // bnb <=> wbnb
        setWethDepositRule(vault, contracts.WBNB());
        setWethWithdrawRule(vault, contracts.WBNB());

        // wbnb => slisbnb
        setSlisDepositRule(vault, contracts.SLIS_BNB_STAKE_MANAGER());

        // slisbnb <=> asbnb
        setApprovalRule(vault, contracts.SLISBNB(), contracts.AS_BNB_MINTER());
        setAstherusMintRule(vault, contracts.AS_BNB_MINTER());
        setAstherusBurnRule(vault, contracts.AS_BNB_MINTER());

        // asbnb <=> kernel
        setApprovalRule(vault_, contracts.ASBNB(), contracts.STAKER_GATEWAY());
        setStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.ASBNB());
        setUnstakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.ASBNB());

        vault_.unpause();

        vault_.processAccounting();

        _renounceTemporaryRoles();
    }
}
