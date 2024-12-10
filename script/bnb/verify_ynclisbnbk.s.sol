// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";

import {BaseVerifyScript} from "script/BaseVerifyScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

// FOUNDRY_PROFILE=mainnet forge script VerifyYnclisBNBkStrategy
contract VerifyYnclisBNBkStrategy is BaseVerifyScript {
    function symbol() public pure override returns (string memory) {
        return "ynclisBNBk";
    }

    function run() public {
        _setup();
        _loadDeployment();

        verify();
    }

    function verify() internal view {
        assertNotEq(address(vault), address(0), "vault is not set");

        assertEq(vault.name(), "YieldNest Restaked clisBNB - Kernel", "name is invalid");
        assertEq(vault.symbol(), "ynclisBNBk", "symbol is invalid");
        assertEq(vault.decimals(), 18, "decimals is invalid");

        assertEq(vault.provider(), address(rateProvider), "provider is invalid");
        assertEq(vault.getStakerGateway(), contracts.STAKER_GATEWAY(), "staker gateway is invalid");
        assertTrue(vault.getHasAllocator(), "has allocator is invalid");
        assertTrue(vault.getSyncDeposit(), "sync deposit is invalid");
        assertTrue(vault.getSyncWithdraw(), "sync withdraw is invalid");

        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());

        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 6, "assets length is invalid");
        assertEq(assets[0], contracts.WBNB(), "assets[0] is invalid");
        IVault.AssetParams memory asset = vault.getAsset(contracts.WBNB());
        assertEq(asset.decimals, 18, "asset[0].decimals is invalid");
        assertEq(asset.active, true, "asset[0].active is invalid");
        assertEq(asset.index, 0, "asset[0].index is invalid");

        assertEq(assets[1], address(stakerGateway.getVault(contracts.CLISBNB())));
        asset = vault.getAsset(address(stakerGateway.getVault(contracts.CLISBNB())));
        assertEq(asset.decimals, 18, "asset[1].decimals is invalid");
        assertEq(asset.active, false, "asset[1].active is invalid");
        assertEq(asset.index, 3, "asset[1].index is invalid");

        validateApprovalRule(vault, contracts.WBNB(), contracts.STAKER_GATEWAY());
        validateStakingRule(vault, contracts.STAKER_GATEWAY(), contracts.WBNB());

        assertFalse(vault.paused());

        _verifyDefaultRoles(vault);
        _verifyTemporaryRoles(vault);

        assertTrue(vault.hasRole(vault.ALLOCATOR_ROLE(), contracts.YNBNBX()));
    }
}
