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
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {MainnetActors} from "script/Actors.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";

contract YnBNBkTest is Test, AssertUtils, MainnetActors, EtchUtils {
    KernelStrategy public vault;
    KernelStrategy public buffer;
    KernelRateProvider public kernelProvider;

    function setUp() public {
        kernelProvider = new KernelRateProvider();
        etchProvider(address(kernelProvider));

        vault = deployMigrateVault();
    }

    function deployMigrateVault() internal returns (KernelStrategy) {
        MigratedKernelStrategy migrationVault = MigratedKernelStrategy(payable(MC.YNBNBk));

        uint256 previousTotalAssets = migrationVault.totalAssets();

        uint256 previousTotalSupply = migrationVault.totalSupply();

        address specificHolder = 0xCfac0990700eD9B67FeFBD4b26a79E426468a419;

        uint256 previousBalance = migrationVault.balanceOf(specificHolder);

        MigratedKernelStrategy implemention = new MigratedKernelStrategy();

        ProxyAdmin proxyAdmin = ProxyAdmin(MC.YNBNBk_PROXY_ADMIN);

        vm.prank(proxyAdmin.owner());

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(MC.YNBNBk),
            address(implemention),
            abi.encodeWithSelector(
                KernelStrategy.initialize.selector,
                address(MainnetActors.ADMIN),
                "YieldNest Restaked BNB - Kernel",
                "ynBNBk",
                18
            )
        );

        MigratedKernelStrategy.Asset[] memory assets = new MigratedKernelStrategy.Asset[](3);

        assets[0] = MigratedKernelStrategy.Asset({asset: MC.WBNB, decimals: 18, active: false});
        assets[1] = MigratedKernelStrategy.Asset({asset: MC.SLISBNB, decimals: 18, active: true});
        assets[2] = MigratedKernelStrategy.Asset({asset: MC.BNBX, decimals: 18, active: true});

        vm.prank(proxyAdmin.owner());

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(MC.YNBNBk),
            address(implemention),
            abi.encodeWithSelector(
                MigratedKernelStrategy.initializeAndMigrate.selector,
                address(MainnetActors.ADMIN),
                "YieldNest Restaked BNB - Kernel",
                "ynBNBk",
                18,
                assets,
                MC.STAKER_GATEWAY,
                false
            )
        );

        vault = KernelStrategy(payable(address(migrationVault)));
        configureVault(vault);

        uint256 newTotalAssets = migrationVault.totalAssets();
        assertEqThreshold(
            newTotalAssets, previousTotalAssets, 1000, "Total assets should remain the same after upgrade"
        );

        uint256 newTotalSupply = migrationVault.totalSupply();
        assertEq(newTotalSupply, previousTotalSupply, "Total supply should remain the same after upgrade");

        uint256 newBalance = migrationVault.balanceOf(specificHolder);
        assertEq(newBalance, previousBalance, "Balance should remain the same after upgrade");

        return vault;
    }

    function configureVault(KernelStrategy vault_) internal {
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

        // set provider
        vault_.setProvider(address(MC.PROVIDER));

        vault_.unpause();

        vm.stopPrank();

        vault_.processAccounting();
    }

    function test_Vault_Upgrade_ERC20_view_functions() public view {
        // Test the name function
        assertEq(
            vault.name(), "YieldNest Restaked BNB - Kernel", "Vault name should be 'YieldNest Restaked BNB - Kernel'"
        );

        // Test the symbol function
        assertEq(vault.symbol(), "ynBNBk", "Vault symbol should be 'ynBNBk'");

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Vault decimals should be 18");

        // Test the totalSupply function
        vault.totalSupply();
    }

    function test_Vault_Upgrade_ERC4626_view_functions() public view {
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
        assertEq(assets.length, 3, "There should be three assets in the vault");
        assertEq(assets[0], MC.WBNB, "First asset should be WBNB");
        assertEq(assets[1], MC.SLISBNB, "Second asset should be SLISBNB");
        assertEq(assets[2], MC.BNBX, "Third asset should be SLISBNB");
    }
}
