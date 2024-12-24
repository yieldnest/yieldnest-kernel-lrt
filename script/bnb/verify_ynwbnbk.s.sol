// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";

import {KernelVerifyScript} from "script/KernelVerifyScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

// FOUNDRY_PROFILE=mainnet forge script VerifyYnWBNBkStrategy
contract VerifyYnWBNBkStrategy is KernelVerifyScript {
    function symbol() public pure override returns (string memory) {
        return "ynWBNBk";
    }

    function run() public {
        _loadDeployment();
        _setup();

        verify();
    }

    function verify() internal view {
        assertNotEq(address(vault_), address(0), "vault is not set");

        assertEq(vault_.name(), "YieldNest WBNB Buffer - Kernel", "name is invalid");
        assertEq(vault_.symbol(), "ynWBNBk", "symbol is invalid");
        assertEq(vault_.decimals(), 18, "decimals is invalid");
        assertEq(vault_.baseWithdrawalFee(), 0, "base withdrawal fee is invalid");
        assertEq(vault_.countNativeAsset(), true, "count native asset is invalid");

        assertEq(vault_.provider(), address(rateProvider), "provider is invalid");
        assertEq(vault_.getStakerGateway(), contracts.STAKER_GATEWAY(), "staker gateway is invalid");
        assertTrue(vault_.getHasAllocator(), "has allocator is invalid");
        assertTrue(vault_.getSyncDeposit(), "sync deposit is invalid");
        assertTrue(vault_.getSyncWithdraw(), "sync withdraw is invalid");
        assertTrue(vault_.alwaysComputeTotalAssets(), "always compute total assets is invalid");
        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());

        address[] memory assets = vault_.getAssets();
        assertEq(assets.length, 6, "assets length is invalid");
        assertEq(assets[0], contracts.WBNB(), "assets[0] is invalid");
        IVault.AssetParams memory asset = vault_.getAsset(contracts.WBNB());
        assertEq(asset.decimals, 18, "asset[0].decimals is invalid");
        assertEq(asset.active, true, "asset[0].active is invalid");
        assertEq(asset.index, 0, "asset[0].index is invalid");

        assertEq(assets[1], address(stakerGateway.getVault(contracts.WBNB())));
        asset = vault_.getAsset(address(stakerGateway.getVault(contracts.WBNB())));
        assertEq(asset.decimals, 18, "asset[1].decimals is invalid");
        assertEq(asset.active, false, "asset[1].active is invalid");
        assertEq(asset.index, 3, "asset[1].index is invalid");

        _verifyApprovalRule(vault_, contracts.WBNB(), contracts.STAKER_GATEWAY());
        _verifyStakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.WBNB());
        _verifyUnstakingRule(vault_, contracts.STAKER_GATEWAY(), contracts.WBNB());

        assertFalse(vault_.paused());

        _verifyDefaultRoles();
        _verifyTemporaryRoles();
        _verifyViewer();

        assertTrue(vault_.hasRole(vault_.ALLOCATOR_ROLE(), contracts.YNBNBX()));
    }
}
