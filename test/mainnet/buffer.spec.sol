// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {EtchUtils} from "test/mainnet/helpers/EtchUtils.sol";
import {SetupVault, Vault, IVault} from "lib/yieldnest-vault/test/mainnet/helpers/SetupVault.sol";
import {MigratedKernelStrategy} from "src/MigratedKernelStrategy.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";
import {KernelRateProvider} from "src/module/KernelRateProvider.sol";
import {ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {MainnetActors} from "script/Actors.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";

contract BufferTest is Test, AssertUtils, MainnetActors, EtchUtils {
    KernelStrategy public vault;
    KernelRateProvider public kernelProvider;

    function setUp() public {
        kernelProvider = new KernelRateProvider();
        etchProvider(address(kernelProvider));

        vault = deployBuffer();
        etchBuffer(address(vault));
    }

    function deployBuffer() internal returns (KernelStrategy) {
        // Deploy implementation contract
        KernelStrategy implementation = new KernelStrategy();

        // Deploy transparent proxy
        bytes memory initData = abi.encodeWithSelector(
            KernelStrategy.initialize.selector, MainnetActors.ADMIN, "YieldNest BNB Buffer - Kernel", "ynWBNBk", 18
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(MainnetActors.ADMIN), initData);

        // Cast proxy to KernelStrategy type
        vault = KernelStrategy(payable(address(proxy)));

        assertEq(vault.symbol(), "ynWBNBk");

        configureBuffer(vault);

        return vault;
    }

    function configureBuffer(KernelStrategy vault_) internal {
        vm.startPrank(ADMIN);

        vault_.grantRole(vault_.PROCESSOR_ROLE(), PROCESSOR);
        vault_.grantRole(vault_.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault_.grantRole(vault_.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault_.grantRole(vault_.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault_.grantRole(vault_.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault_.grantRole(vault_.PAUSER_ROLE(), PAUSER);
        vault_.grantRole(vault_.UNPAUSER_ROLE(), UNPAUSER);

        // set allocator to admin for now
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), address(ADMIN));

        // set strategy manager to admin for now
        vault_.grantRole(vault_.STRATEGY_MANAGER_ROLE(), address(ADMIN));

        vault_.setProvider(address(MC.PROVIDER));

        vault_.setStakerGateway(MC.STAKER_GATEWAY);

        vault_.addAsset(MC.WBNB, 18, true);

        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
    }

    function test_Buffer_Vault_ERC20_view_functions() public view {
        // Test the name function
        assertEq(vault.name(), "YieldNest BNB Buffer - Kernel", "Vault name should be 'YieldNest BNB Buffer - Kernel'");

        // Test the symbol function
        assertEq(vault.symbol(), "ynWBNBk", "Vault symbol should be 'ynWBNBk'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        vault.totalSupply();
    }

    function test_Buffer_Vault_ERC4626_view_functions() public view {
        // Test the paused function
        assertFalse(vault.paused(), "Vault should not be paused");

        // Test the asset function
        assertEq(address(vault.asset()), MC.WBNB, "Vault asset should be WBNB");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        assertGe(totalAssets, totalSupply, "TotalAssets should be greater than totalSupply");

        // Test the convertToShares function
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);
        assertLe(shares, amount, "Shares should be less or equal to amount deposited");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertEqThreshold(convertedAssets, amount, 3, "Converted assets should be close to amount deposited");

        // Test the maxDeposit function
        uint256 maxDeposit = vault.maxDeposit(address(this));
        assertGt(maxDeposit, 0, "Max deposit should be greater than 0");

        // Test the maxMint function
        uint256 maxMint = vault.maxMint(address(this));
        assertGt(maxMint, 0, "Max mint should be greater than 0");

        // Test the maxWithdraw function
        uint256 maxWithdraw = vault.maxWithdraw(address(this));
        assertEq(maxWithdraw, 0, "Max withdraw should be zero");

        // Test the maxRedeem function
        uint256 maxRedeem = vault.maxRedeem(address(this));
        assertEq(maxRedeem, 0, "Max redeem should be zero");

        // Test the getAssets function
        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 1, "There should be only one asset in the vault");
        assertEq(assets[0], MC.WBNB, "First asset should be WBNB");
    }
}
