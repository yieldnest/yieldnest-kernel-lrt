// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {KernelVerifyScript} from "script/KernelVerifyScript.sol";

// FOUNDRY_PROFILE=mainnet forge script VerifyYnBfBTCkStrategy
contract VerifyYnBfBTCkStrategy is KernelVerifyScript {
    function symbol() public pure override returns (string memory) {
        return "ynBfBTCk";
    }

    function run() public {
        _loadDeployment();
        _setup();

        verify();
    }

    function verify() internal view {
        assertNotEq(address(vault_), address(0), "vault is not set");

        assertEq(vault_.name(), "YieldNest Restaked BitFi BTC - Kernel", "name is invalid");
        assertEq(vault_.symbol(), "ynBfBTCk", "symbol is invalid");
        assertEq(vault_.decimals(), 8, "decimals is invalid");

        assertEq(vault_.provider(), address(rateProvider), "provider is invalid");
        assertEq(vault_.getStakerGateway(), contracts.STAKER_GATEWAY(), "staker gateway is invalid");
        assertFalse(vault_.getHasAllocator(), "has allocator is invalid");
        assertFalse(vault_.getSyncDeposit(), "sync deposit is invalid");
        assertFalse(vault_.getSyncWithdraw(), "sync withdraw is invalid");
        assertEq(vault_.baseWithdrawalFee(), 0, "base withdrawal fee is invalid");
        assertEq(vault_.countNativeAsset(), false, "count native asset is invalid");
        assertTrue(vault_.alwaysComputeTotalAssets(), "always compute total assets is invalid");

        address[] memory assets = vault_.getAssets();
        assertEq(assets.length, 1, "assets length is invalid");

        assertEq(assets[0], contracts.BFBTC(), "assets[0] is invalid");
        IVault.AssetParams memory asset = vault_.getAsset(contracts.BFBTC());
        assertEq(asset.decimals, 8, "asset[0].decimals is invalid");
        assertEq(asset.index, 0, "asset[0].index is invalid");
        assertEq(asset.active, true, "asset[0].active is invalid");
        assertEq(vault_.getAssetWithdrawable(contracts.BFBTC()), true, "asset[0].withdrawable is invalid");

        // IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());
        // assertEq(assets[1], address(stakerGateway.getVault(contracts.BFBTC())));
        // asset = vault_.getAsset(address(stakerGateway.getVault(contracts.BFBTC())));
        // assertEq(asset.decimals, 8, "asset[1].decimals is invalid");
        // assertEq(asset.active, false, "asset[1].active is invalid");
        // assertEq(asset.index, 1, "asset[1].index is invalid");
        // _verifyApprovalRule(vault_, contracts.BFBTC(), contracts.STAKER_GATEWAY());
        // _verifyStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.BFBTC());
        // _verifyUnstakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.BFBTC());

        assertFalse(vault_.paused());

        _verifyDefaultRoles();
        _verifyTemporaryRoles();
        _verifyViewer();
    }
}
