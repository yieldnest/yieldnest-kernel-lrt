// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {BTCRateProvider, TestnetBTCRateProvider} from "src/module/BTCRateProvider.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {BaseVerifyScript} from "script/BaseVerifyScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {Test} from "lib/forge-std/src/Test.sol";

// FOUNDRY_PROFILE=mainnet forge script VerifyYnBTCkStrategy
contract VerifyYnBTCkStrategy is BaseVerifyScript {
    function symbol() public pure override returns (string memory) {
        return "ynBTCk";
    }

    function run() public {
        _setup();
        _loadDeployment();

        verify();
    }

    function verify() internal view {
        assertNotEq(address(vault), address(0), "vault is not set");

        assertEq(vault.name(), "YieldNest Restaked BTC - Kernel", "name is invalid");
        assertEq(vault.symbol(), "ynBTCk", "symbol is invalid");
        assertEq(vault.decimals(), 18, "decimals is invalid");

        assertEq(vault.provider(), address(rateProvider), "provider is invalid");
        assertEq(vault.getStakerGateway(), contracts.STAKER_GATEWAY(), "staker gateway is invalid");
        assertFalse(vault.getHasAllocator(), "has allocator is invalid");
        assertTrue(vault.getSyncDeposit(), "sync deposit is invalid");
        assertTrue(vault.getSyncWithdraw(), "sync withdraw is invalid");

        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());

        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 6, "assets length is invalid");
        assertEq(assets[0], contracts.BTCB(), "assets[0] is invalid");
        IVault.AssetParams memory asset = vault.getAsset(contracts.BTCB());
        assertEq(asset.decimals, 18, "asset[0].decimals is invalid");
        assertEq(asset.active, true, "asset[0].active is invalid");
        assertEq(asset.index, 0, "asset[0].index is invalid");
        assertEq(assets[1], contracts.SOLVBTC());
        assertEq(assets[2], contracts.SOLVBTC_BNN());
        assertEq(assets[3], address(stakerGateway.getVault(contracts.BTCB())));
        assertEq(assets[4], address(stakerGateway.getVault(contracts.SOLVBTC())));
        assertEq(assets[5], address(stakerGateway.getVault(contracts.SOLVBTC_BNN())));

        validateApprovalRule(vault, contracts.BTCB(), contracts.STAKER_GATEWAY());
        validateApprovalRule(vault, contracts.SOLVBTC(), contracts.STAKER_GATEWAY());
        validateApprovalRule(vault, contracts.SOLVBTC_BNN(), contracts.STAKER_GATEWAY());

        address[] memory assetsForStaking = new address[](3);
        assets[0] = contracts.BTCB();
        assets[1] = contracts.SOLVBTC();
        assets[2] = contracts.SOLVBTC_BNN();
        validateStakingRule(vault, contracts.STAKER_GATEWAY(), assetsForStaking);

        assertFalse(vault.paused());

        _verifyDefaultRoles(vault);
        _verifyTemporaryRoles(vault);
    }

}
