// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider, Vault} from "lib/yieldnest-vault/script/BaseScript.sol";

import {KernelClisStrategy} from "src/KernelClisStrategy.sol";
import {BNBRateProvider} from "src/module/BNBRateProvider.sol";
import {TestnetBNBRateProvider} from "test/module/BNBRateProvider.sol";

import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseKernelScript} from "script/BaseKernelScript.sol";

import {KernelClisVaultViewer} from "src/utils/KernelClisVaultViewer.sol";
import {BaseVaultViewer, KernelVaultViewer} from "src/utils/KernelVaultViewer.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployYnclisBNBkStrategy --sender 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract DeployYnclisBNBkStrategy is BaseKernelScript {
    function symbol() public pure override returns (string memory) {
        return "ynclisBNBk";
    }

    function deployRateProvider() internal {
        if (block.chainid == 97) {
            rateProvider = IProvider(address(new TestnetBNBRateProvider()));
        }

        if (block.chainid == 56) {
            rateProvider = IProvider(address(new BNBRateProvider()));
        }
    }

    function deployViewer() internal {
        viewerImplementation = new KernelClisVaultViewer();

        bytes memory initData = abi.encodeWithSelector(BaseVaultViewer.initialize.selector, address(vault));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(viewerImplementation), actors_.ADMIN(), initData);

        viewer = KernelVaultViewer(payable(address(proxy)));
    }

    function run() public {
        vm.startBroadcast();

        _setup();
        _deployTimelockController();
        deployRateProvider();

        _verifySetup();

        deploy();

        deployViewer();

        _saveDeployment();

        vm.stopBroadcast();
    }

    function deploy() internal {
        implementation = Vault(payable(address(new KernelClisStrategy())));

        address admin = msg.sender;
        string memory name = "YieldNest Restaked clisBNB - Kernel";
        string memory symbol_ = symbol();
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
            new TransparentUpgradeableProxy(address(implementation), address(timelock), initData);

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
        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());
        vault_.addAssetWithDecimals(stakerGateway.getVault(contracts.CLISBNB()), 18, false);

        vault_.unpause();

        // approval not required since we send native tokens
        setClisStakingRule(vault_, contracts.STAKER_GATEWAY());
        setClisUnstakingRule(vault_, contracts.STAKER_GATEWAY());

        // wbnb
        setWethDepositRule(vault, contracts.WBNB());
        setWethWithdrawRule(vault, contracts.WBNB());

        vault_.processAccounting();

        _renounceTemporaryRoles();
    }
}
