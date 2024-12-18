// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {BaseVerifyScript} from "script/BaseVerifyScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

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
        assertEq(vault.baseWithdrawalFee(), 100000, "base withdrawal fee is invalid");
        assertEq(vault.countNativeAsset(), false, "count native asset is invalid");
        assertTrue(vault.alwaysComputeTotalAssets(), "always compute total assets is invalid");
        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());

        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 6, "assets length is invalid");
        assertEq(assets[0], contracts.BTCB(), "assets[0] is invalid");
        IVault.AssetParams memory asset = vault.getAsset(contracts.BTCB());
        assertEq(asset.decimals, 18, "asset[0].decimals is invalid");
        assertEq(asset.active, true, "asset[0].active is invalid");
        assertEq(asset.index, 0, "asset[0].index is invalid");

        assertEq(assets[1], contracts.SOLVBTC());
        asset = vault.getAsset(contracts.SOLVBTC());
        assertEq(asset.decimals, 18, "asset[1].decimals is invalid");
        assertEq(asset.active, true, "asset[1].active is invalid");
        assertEq(asset.index, 1, "asset[1].index is invalid");

        assertEq(assets[2], contracts.SOLVBTC_BBN());
        asset = vault.getAsset(contracts.SOLVBTC_BBN());
        assertEq(asset.decimals, 18, "asset[2].decimals is invalid");
        assertEq(asset.active, true, "asset[2].active is invalid");
        assertEq(asset.index, 2, "asset[2].index is invalid");

        assertEq(assets[3], address(stakerGateway.getVault(contracts.BTCB())));
        asset = vault.getAsset(address(stakerGateway.getVault(contracts.BTCB())));
        assertEq(asset.decimals, 18, "asset[3].decimals is invalid");
        assertEq(asset.active, false, "asset[3].active is invalid");
        assertEq(asset.index, 3, "asset[3].index is invalid");

        assertEq(assets[4], address(stakerGateway.getVault(contracts.SOLVBTC())));
        asset = vault.getAsset(address(stakerGateway.getVault(contracts.SOLVBTC())));
        assertEq(asset.decimals, 18, "asset[4].decimals is invalid");
        assertEq(asset.active, false, "asset[4].active is invalid");
        assertEq(asset.index, 4, "asset[4].index is invalid");

        assertEq(assets[5], address(stakerGateway.getVault(contracts.SOLVBTC_BBN())));
        asset = vault.getAsset(address(stakerGateway.getVault(contracts.SOLVBTC_BBN())));
        assertEq(asset.decimals, 18, "asset[5].decimals is invalid");
        assertEq(asset.active, false, "asset[5].active is invalid");
        assertEq(asset.index, 5, "asset[5].index is invalid");

        _verifyApprovalRule(vault, contracts.BTCB(), contracts.STAKER_GATEWAY());
        _verifyApprovalRule(vault, contracts.SOLVBTC(), contracts.STAKER_GATEWAY());
        _verifyApprovalRule(vault, contracts.SOLVBTC_BBN(), contracts.STAKER_GATEWAY());

        address[] memory assetsForStaking = new address[](3);
        assetsForStaking[0] = contracts.BTCB();
        assetsForStaking[1] = contracts.SOLVBTC();
        assetsForStaking[2] = contracts.SOLVBTC_BBN();
        _verifyStakingRule(vault, contracts.STAKER_GATEWAY(), assetsForStaking);
        _verifyUnstakingRule(vault, contracts.STAKER_GATEWAY(), assetsForStaking);

        assertFalse(vault.paused());

        _verifyDefaultRoles(vault);
        _verifyTemporaryRoles(vault);
        _verifyViewer();
    }
}
