// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {KernelVerifyScript} from "script/KernelVerifyScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

// FOUNDRY_PROFILE=mainnet forge script VerifyYnBTCkStrategy
contract VerifyYnBTCkStrategy is KernelVerifyScript {
    function symbol() public pure override returns (string memory) {
        return "ynBTCk";
    }

    function run() public {
        _loadDeployment();
        _setup();

        verify();
    }

    function verify() internal view {
        assertNotEq(address(vault_), address(0), "vault is not set");

        assertEq(vault_.name(), "YieldNest Restaked BTC - Kernel", "name is invalid");
        assertEq(vault_.symbol(), "ynBTCk", "symbol is invalid");
        assertEq(vault_.decimals(), 18, "decimals is invalid");

        assertEq(vault_.provider(), address(rateProvider), "provider is invalid");
        assertEq(vault_.getStakerGateway(), contracts.STAKER_GATEWAY(), "staker gateway is invalid");
        assertFalse(vault_.getHasAllocator(), "has allocator is invalid");
        assertTrue(vault_.getSyncDeposit(), "sync deposit is invalid");
        assertTrue(vault_.getSyncWithdraw(), "sync withdraw is invalid");
        assertEq(vault_.baseWithdrawalFee(), 100000, "base withdrawal fee is invalid");
        assertEq(vault_.countNativeAsset(), false, "count native asset is invalid");
        assertTrue(vault_.alwaysComputeTotalAssets(), "always compute total assets is invalid");
        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());

        address[] memory assets = vault_.getAssets();
        assertEq(assets.length, 6, "assets length is invalid");
        assertEq(assets[0], contracts.BTCB(), "assets[0] is invalid");
        IVault.AssetParams memory asset = vault_.getAsset(contracts.BTCB());
        assertEq(asset.decimals, 18, "asset[0].decimals is invalid");
        assertEq(asset.active, true, "asset[0].active is invalid");
        assertEq(asset.index, 0, "asset[0].index is invalid");

        assertEq(assets[1], contracts.SOLVBTC());
        asset = vault_.getAsset(contracts.SOLVBTC());
        assertEq(asset.decimals, 18, "asset[1].decimals is invalid");
        assertEq(asset.active, true, "asset[1].active is invalid");
        assertEq(asset.index, 1, "asset[1].index is invalid");

        assertEq(assets[2], contracts.SOLVBTC_BBN());
        asset = vault_.getAsset(contracts.SOLVBTC_BBN());
        assertEq(asset.decimals, 18, "asset[2].decimals is invalid");
        assertEq(asset.active, true, "asset[2].active is invalid");
        assertEq(asset.index, 2, "asset[2].index is invalid");

        assertEq(assets[3], address(stakerGateway.getVault(contracts.BTCB())));
        asset = vault_.getAsset(address(stakerGateway.getVault(contracts.BTCB())));
        assertEq(asset.decimals, 18, "asset[3].decimals is invalid");
        assertEq(asset.active, false, "asset[3].active is invalid");
        assertEq(asset.index, 3, "asset[3].index is invalid");

        assertEq(assets[4], address(stakerGateway.getVault(contracts.SOLVBTC())));
        asset = vault_.getAsset(address(stakerGateway.getVault(contracts.SOLVBTC())));
        assertEq(asset.decimals, 18, "asset[4].decimals is invalid");
        assertEq(asset.active, false, "asset[4].active is invalid");
        assertEq(asset.index, 4, "asset[4].index is invalid");

        assertEq(assets[5], address(stakerGateway.getVault(contracts.SOLVBTC_BBN())));
        asset = vault_.getAsset(address(stakerGateway.getVault(contracts.SOLVBTC_BBN())));
        assertEq(asset.decimals, 18, "asset[5].decimals is invalid");
        assertEq(asset.active, false, "asset[5].active is invalid");
        assertEq(asset.index, 5, "asset[5].index is invalid");

        _verifyApprovalRule(vault_, contracts.BTCB(), contracts.STAKER_GATEWAY());
        _verifyApprovalRule(vault_, contracts.SOLVBTC(), contracts.STAKER_GATEWAY());
        _verifyApprovalRule(vault_, contracts.SOLVBTC_BBN(), contracts.STAKER_GATEWAY());

        address[] memory assetsForStaking = new address[](3);
        assetsForStaking[0] = contracts.BTCB();
        assetsForStaking[1] = contracts.SOLVBTC();
        assetsForStaking[2] = contracts.SOLVBTC_BBN();
        _verifyStakingRule(vault_, contracts.STAKER_GATEWAY(), assetsForStaking);
        _verifyUnstakingRule(vault_, contracts.STAKER_GATEWAY(), assetsForStaking);

        assertFalse(vault_.paused());

        _verifyDefaultRoles();
        _verifyTemporaryRoles();
        _verifyViewer();
    }
}
