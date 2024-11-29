// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SetupVault, Vault, IVault} from "lib/yieldnest-vault/test/mainnet/helpers/SetupVault.sol";
import {Etches} from "lib/yieldnest-vault/test/mainnet/helpers/Etches.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";
import {ITransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";
import {Provider} from "lib/yieldnest-vault/src/module/Provider.sol";
import {MigrateKernelStrategy} from "src/MigrateKernelStrategy.sol";
import {MainnetActors} from "script/Actors.sol";

contract VaultMainnetUpgradeTest is Test, AssertUtils, MainnetActors, Etches {
    Vault public maxVault;
    MigrateKernelStrategy public vault;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        maxVault = setupVault.deploy();

        vault = MigrateKernelStrategy(payable(MC.YNBNBk));

        uint256 previousTotalAssets = vault.totalAssets();

        uint256 previousTotalSupply = vault.totalSupply();

        address specificHolder = 0xCfac0990700eD9B67FeFBD4b26a79E426468a419;

        uint256 previousBalance = vault.balanceOf(specificHolder);

        MigrateKernelStrategy implemention = new MigrateKernelStrategy();

        // TODO: move admin to actors
        vm.prank(0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a);
        ProxyAdmin proxyAdmin = ProxyAdmin(MC.YNBNBk_PROXY_ADMIN);

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(MC.YNBNBk),
            address(implemention),
            abi.encodeWithSelector(
                MigrateKernelStrategy.initializeAndMigrate.selector,
                address(MainnetActors.ADMIN),
                "YieldNest BNB Kernel", 
                "ynBNBk", 
                18
            )
        );


        uint256 newTotalAssets = vault.totalAssets();
        assertEq(newTotalAssets, previousTotalAssets, "Total assets should remain the same after upgrade");

        uint256 newTotalSupply = vault.totalSupply();
        assertEq(newTotalSupply, previousTotalSupply, "Total supply should remain the same after upgrade");

        uint256 newBalance = vault.balanceOf(specificHolder);
        assertEq(newBalance, previousBalance, "Balance should remain the same after upgrade");

        configureVault();

    }

    function configureVault() internal {

        // etch to mock ETHRate provider and Buffer
        mockAll();

        vm.startPrank(ADMIN);
        
        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.ALLOCATOR_ROLE(), address(maxVault));

        vault.setProvider(MC.PROVIDER);

        // TODO: add deposit rules to be able to stake to the kernel staker gateway
        // setDepositRule(vault, MC.BUFFER, address(vault));
        // setDepositRule(vault, MC.YNBNBk, address(vault));
        // setWethDepositRule(vault, MC.WBNB);
        //
        // setApprovalRule(vault, address(vault), MC.BUFFER);
        // setApprovalRule(vault, MC.WBNB, MC.BUFFER);
        // setApprovalRule(vault, address(vault), MC.YNBNBk);
        // setApprovalRule(vault, MC.SLISBNB, MC.YNBNBk);

        vault.unpause();

        vm.stopPrank();

        vault.processAccounting();
    }

    function test_Vault_Upgrade_ERC20_view_functions() public view {
        // Test the name function
        assertEq(vault.name(), "YieldNest BNB Kernel", "Vault name should be 'YieldNest BNB Kernel'");

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
        assertEq(address(vault.asset()), MC.SLISBNB, "Vault asset should be WBNB");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        assertGe(totalAssets, totalSupply, "TotalAssets should be greater than totalSupply");

        // Test the convertToShares function
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);
        console.log(shares);
        assertGe(shares, amount, "Shares should greater or equal to amount deposited");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        console.log(convertedAssets);
        // TODO: fix this test
        // assertEqThreshold(convertedAssets, amount, 3, "Converted assets should be close to amount deposited");

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
        assertEq(assets[0], MC.SLISBNB, "First asset should be SLISBNB");
    }

}
