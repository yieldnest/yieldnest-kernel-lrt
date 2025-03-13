// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MainnetContracts} from "script/Contracts.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {console} from "lib/forge-std/src/console.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {ProxyAdmin} from "lib/yieldnest-vault/src/Common.sol";
import {BTCRateProvider} from "src/module/BTCRateProvider.sol";

import {console} from "lib/forge-std/src/console.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";

contract YnBTCkForkTest is BaseForkTest {
    function setUp() public {
        vault = KernelStrategy(payable(address(MainnetContracts.YNBTCK)));
        stakerGateway = IStakerGateway(vault.getStakerGateway());

        asset = IERC20(MainnetContracts.BTCB);
    }

    function _upgradeVault() internal override {
        KernelStrategy newImplementation = new KernelStrategy();

        // TODO: uncomment this when we have a timelock and remove repeated code
        // _upgradeVaultWithTimelock(address(newImplementation));

        // Get proxy admin
        ProxyAdmin proxyAdmin = ProxyAdmin(getProxyAdmin(address(vault)));

        assertEq(proxyAdmin.owner(), ADMIN, "Proxy admin owner should be admin");

        vm.startPrank(ADMIN);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(payable(address(vault))), address(newImplementation), "");
        vm.stopPrank();

        // Verify upgrade was successful
        assertEq(
            getImplementation(address(vault)),
            address(newImplementation),
            "Implementation address should match new implementation"
        );

        // Set Enzo BTC and BTCB as withdrawable
        vm.startPrank(ADMIN);
        KernelStrategy(payable(address(vault))).setAssetWithdrawable(MainnetContracts.ENZOBTC, true);
        KernelStrategy(payable(address(vault))).setAssetWithdrawable(MainnetContracts.BTCB, true);
        KernelStrategy(payable(address(vault))).setAssetWithdrawable(MainnetContracts.SOLVBTC_BBN, true);
        KernelStrategy(payable(address(vault))).setAssetWithdrawable(MainnetContracts.SOLVBTC, true);

        // Grant FEE_MANAGER_ROLE to ADMIN
        KernelStrategy(payable(address(vault))).grantRole(
            KernelStrategy(payable(address(vault))).FEE_MANAGER_ROLE(), ADMIN
        );
        // Set base withdrawal fee to 0 - not called here to test invariants; test this individually
        //KernelStrategy(payable(address(vault))).setBaseWithdrawalFee(0);
        vm.stopPrank();
    }

    function testUpgrade() public {
        _testVaultUpgrade();
    }

    function testDepositBeforeUpgrade() public {
        _depositIntoVault(alice, 100 ether);
    }

    function testDepositAfterUpgrade() public {
        _upgradeVault();
        _depositIntoVault(alice, 100 ether);
    }

    function testWithdrawBeforeUpgrade() public {
        _depositIntoVault(alice, 100 ether);
        _withdrawFromVault(alice, 50 ether);
    }

    function testWithdrawAfterUpgrade() public {
        _depositIntoVault(alice, 100 ether);
        _upgradeVault();
        _withdrawFromVault(alice, 50 ether);
    }

    function testAddRoleAndDeactivateAsset() public {
        _upgradeVault();
        _addRoleAndModifyAsset(MainnetContracts.SOLVBTC, false);
    }

    function testAddRoleAndAddFee() public {
        _upgradeVault();
        _addRoleAndAddFee();
    }

    // Use specific address for testing
    address specificUser = 0x033fDd2d046bD201d45Ea7813e75cB0c63f93AD8;

    function testWithdrawAllBTCBAfterUpgrade() public {
        _upgradeVault();

        // Set base withdrawal fee to 0
        vm.startPrank(ADMIN);
        KernelStrategy(payable(address(vault))).setBaseWithdrawalFee(0);
        vm.stopPrank();

        // Get user's share balance
        uint256 userShares = vault.balanceOf(specificUser);

        // Get the BTCB balance of the vault
        uint256 btcbBalance = stakerGateway.balanceOf(address(asset), address(vault));
        // Store total assets before withdrawal
        uint256 totalAssetsBefore = vault.totalAssets();

        // Calculate the exchange rate before withdrawal
        uint256 rateBeforeWithdraw = vault.convertToAssets(1e18);

        // Withdraw based on BTCB balance of vault
        vm.startPrank(specificUser);
        KernelStrategy(payable(address(vault))).withdrawAsset(address(asset), btcbBalance, specificUser, specificUser);
        vm.stopPrank();

        // Calculate the exchange rate after withdrawal
        uint256 rateAfterWithdraw = vault.convertToAssets(1e18);

        // Store total assets after withdrawal
        uint256 totalAssetsAfter = vault.totalAssets();

        // Log the BTCB balance that was withdrawn
        console.log("BTCB balance withdrawn:", btcbBalance);
        // Log the exchange rate after withdrawal
        console.log("Exchange rate after withdrawal:", rateAfterWithdraw);

        // Log the total assets after withdrawal
        console.log("Total assets after withdrawal:", totalAssetsAfter);

        // Verify user has withdrawn the BTCB
        assertEq(asset.balanceOf(specificUser), btcbBalance, "User should have received the BTCB balance");

        // Verify total assets decreased by the withdrawn amount
        assertEq(totalAssetsBefore - btcbBalance, totalAssetsAfter, "Total assets should decrease by withdrawn amount");

        // Verify the exchange rate remains the same
        assertEq(rateBeforeWithdraw, rateAfterWithdraw, "Exchange rate should remain the same after withdrawal");
    }

    function testDepositSolvBTCRevert() public {
        // Get the solvBTC token address
        address solvBTC = MainnetContracts.SOLVBTC;

        // Deal some solvBTC to the specificUser
        uint256 depositAmount = 1 ether;
        deal(solvBTC, specificUser, depositAmount);

        // Verify the user has the solvBTC
        assertEq(IERC20(solvBTC).balanceOf(specificUser), depositAmount, "User should have solvBTC");

        // Try to deposit solvBTC and expect a revert
        vm.startPrank(specificUser);
        IERC20(solvBTC).approve(address(vault), depositAmount);

        // Verify that maxWithdraw for solvBTC is 0
        uint256 maxWithdrawAmount = KernelStrategy(payable(address(vault))).maxWithdrawAsset(solvBTC, specificUser);
        assertEq(maxWithdrawAmount, 0, "maxWithdraw for solvBTC should be 0");

        // Verify that maxRedeemAsset for solvBTC is also 0
        uint256 maxRedeemAmount = KernelStrategy(payable(address(vault))).maxRedeemAsset(solvBTC, specificUser);
        assertEq(maxRedeemAmount, 0, "maxRedeemAsset for solvBTC should be 0");

        // The deposit should revert because solvBTC is not an accepted asset
        vm.expectRevert();
        vault.deposit(depositAmount, specificUser);

        vm.stopPrank();
    }

    function testAssetsAfterUpgrade() public {
        _upgradeVault();

        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 8, "Should have 2 assets");
        assertEq(vault.asset(), MainnetContracts.BTCB, "Asset should be BTCB");

        address[] memory underlyingAssets = new address[](4);
        underlyingAssets[0] = MainnetContracts.BTCB;
        underlyingAssets[1] = MainnetContracts.ENZOBTC;
        underlyingAssets[2] = MainnetContracts.SOLVBTC;
        underlyingAssets[3] = MainnetContracts.SOLVBTC_BBN;

        for (uint256 i; i < underlyingAssets.length; ++i) {
            address kernelVault = stakerGateway.getVault(underlyingAssets[i]);
            uint256 assetIndex = _checkForAsset(underlyingAssets[i]);
            bool depositable = false;
            if (underlyingAssets[i] == MainnetContracts.ENZOBTC || underlyingAssets[i] == MainnetContracts.BTCB) {
                depositable = true;
            }
            uint8 decimals = 18;
            if (underlyingAssets[i] == MainnetContracts.ENZOBTC) {
                decimals = 8;
            }
            _checkAssetMetadata(underlyingAssets[i], assetIndex, decimals, depositable, true);
            uint256 kernelVaultIndex = _checkForAsset(kernelVault);
            _checkAssetMetadata(kernelVault, kernelVaultIndex, decimals, false, false);
        }
    }

    function testAddAsset() public {
        _upgradeVault();

        address newAsset = MainnetContracts.COBTC;

        vm.expectRevert();
        vault.addAsset(newAsset, true);

        vm.startPrank(ADMIN);
        vault.addAsset(newAsset, true);
        vm.stopPrank();

        assertEq(vault.getAssets().length, 9, "Should have 3 assets");

        uint256 index = _checkForAsset(newAsset);
        _checkAssetMetadata(newAsset, index, 8, true, false);
    }

    function testAddAssetWithDecimals() public {
        _upgradeVault();

        address newAsset = MainnetContracts.COBTC;

        vm.expectRevert();
        vault.addAssetWithDecimals(newAsset, 8, true);

        vm.startPrank(ADMIN);
        vault.addAssetWithDecimals(newAsset, 8, true);
        vm.stopPrank();

        assertEq(vault.getAssets().length, 9, "Should have 3 assets");

        uint256 index = _checkForAsset(newAsset);
        _checkAssetMetadata(newAsset, index, 8, true, true);
    }

    function testAddAssetWithDepositableAndWithdrawable() public {
        _upgradeVault();

        address newAsset = MainnetContracts.COBTC;

        vm.expectRevert();
        vault.addAssetWithDecimals(newAsset, 8, true);

        vm.startPrank(ADMIN);
        vault.addAsset(newAsset, 8, true, false);
        vm.stopPrank();

        assertEq(vault.getAssets().length, 9, "Should have 3 assets");

        uint256 index = _checkForAsset(newAsset);
        _checkAssetMetadata(newAsset, index, 8, true, false);

        vm.startPrank(ADMIN);
        vault.setAssetWithdrawable(newAsset, true);
        vm.stopPrank();

        _checkAssetMetadata(newAsset, index, 8, true, true);
    }

    function testDisableFees() public {
        _upgradeVault();
        _disableFees();

        assertEq(vault.baseWithdrawalFee(), 0, "Base withdrawal fee should be 0");
    }

    function testWithdrawAllSolvBTC() public {
        _upgradeVault();

        uint256 balance = stakerGateway.balanceOf(MainnetContracts.SOLVBTC, address(vault));

        _withdrawFromVault(MainnetContracts.SOLVBTC, specificUser, balance);

        assertEq(stakerGateway.balanceOf(MainnetContracts.SOLVBTC, address(vault)), 0, "Should have 0 balance");
    }

    function testWithdrawAllSolvBTCBBN() public {
        _upgradeVault();

        uint256 balance = stakerGateway.balanceOf(MainnetContracts.SOLVBTC_BBN, address(vault));

        _withdrawFromVault(MainnetContracts.SOLVBTC_BBN, specificUser, balance);

        assertEq(stakerGateway.balanceOf(MainnetContracts.SOLVBTC_BBN, address(vault)), 0, "Should have 0 balance");
    }

    function _checkForAsset(address assetAddress) internal view returns (uint256 index) {
        address[] memory assets = vault.getAssets();
        bool isIncluded = false;

        for (uint256 i; i < assets.length;) {
            if (assets[i] == assetAddress) {
                isIncluded = true;
                index = i;
                break;
            }
            {
                i++;
            }
        }

        assertTrue(isIncluded, "Asset should be included");
    }

    function _checkAssetMetadata(
        address assetAddress,
        uint256 index,
        uint8 decimals,
        bool depositable,
        bool withdrawable
    ) internal view {
        IVault.AssetParams memory params = vault.getAsset(assetAddress);

        assertEq(params.index, index, "Asset index should be correct");
        assertEq(params.decimals, decimals, "Asset decimals should be correct");
        assertEq(params.active, depositable, "Asset depositable should be correct");
        assertEq(vault.getAssetWithdrawable(assetAddress), withdrawable, "Asset withdrawable should be correct");
    }

    function _disableFees() internal {
        vm.startPrank(ADMIN);
        KernelStrategy(payable(address(vault))).setBaseWithdrawalFee(0);
        vm.stopPrank();
    }
}
