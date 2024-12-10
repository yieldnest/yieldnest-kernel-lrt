// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/BaseVault.sol";

import {BaseVerifyScript} from "script/BaseVerifyScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

// FOUNDRY_PROFILE=mainnet forge script VerifyYnBNBkStrategy
contract VerifyYnBNBkStrategy is BaseVerifyScript {
    function symbol() public pure override returns (string memory) {
        return "ynBNBk";
    }

    function run() public {
        _setup();
        _loadDeployment();

        verify();
    }

    function verify() internal view {
        assertNotEq(address(vault), address(0), "vault is not set");

        assertEq(vault.name(), "YieldNest Restaked BNB - Kernel", "name is invalid");
        assertEq(vault.symbol(), "ynBNBk", "symbol is invalid");
        assertEq(vault.decimals(), 18, "decimals is invalid");

        assertEq(vault.provider(), address(rateProvider), "provider is invalid");
        assertEq(vault.getStakerGateway(), contracts.STAKER_GATEWAY(), "staker gateway is invalid");
        assertFalse(vault.getHasAllocator(), "has allocator is invalid");
        assertFalse(vault.getSyncDeposit(), "sync deposit is invalid");
        assertTrue(vault.getSyncWithdraw(), "sync withdraw is invalid");

        IStakerGateway stakerGateway = IStakerGateway(contracts.STAKER_GATEWAY());

        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 6, "assets length is invalid");
        assertEq(assets[0], contracts.WBNB(), "assets[0] is invalid");
        IVault.AssetParams memory asset = vault.getAsset(contracts.WBNB());
        assertEq(asset.decimals, 18, "asset[0].decimals is invalid");
        assertEq(asset.active, false, "asset[0].active is invalid");
        assertEq(asset.index, 0, "asset[0].index is invalid");

        assertEq(assets[1], contracts.SLISBNB());
        asset = vault.getAsset(contracts.SLISBNB());
        assertEq(asset.decimals, 18, "asset[1].decimals is invalid");
        assertEq(asset.active, true, "asset[1].active is invalid");
        assertEq(asset.index, 1, "asset[1].index is invalid");

        assertEq(assets[2], contracts.BNBX());
        asset = vault.getAsset(contracts.BNBX());
        assertEq(asset.decimals, 18, "asset[2].decimals is invalid");
        assertEq(asset.active, true, "asset[2].active is invalid");
        assertEq(asset.index, 2, "asset[2].index is invalid");

        assertEq(assets[3], address(stakerGateway.getVault(contracts.WBNB())));
        asset = vault.getAsset(address(stakerGateway.getVault(contracts.WBNB())));
        assertEq(asset.decimals, 18, "asset[3].decimals is invalid");
        assertEq(asset.active, false, "asset[3].active is invalid");
        assertEq(asset.index, 3, "asset[3].index is invalid");

        assertEq(assets[4], address(stakerGateway.getVault(contracts.SLISBNB())));
        asset = vault.getAsset(address(stakerGateway.getVault(contracts.SLISBNB())));
        assertEq(asset.decimals, 18, "asset[4].decimals is invalid");
        assertEq(asset.active, false, "asset[4].active is invalid");
        assertEq(asset.index, 4, "asset[4].index is invalid");

        assertEq(assets[5], address(stakerGateway.getVault(contracts.BNBX())));
        asset = vault.getAsset(address(stakerGateway.getVault(contracts.BNBX())));
        assertEq(asset.decimals, 18, "asset[5].decimals is invalid");
        assertEq(asset.active, false, "asset[5].active is invalid");
        assertEq(asset.index, 5, "asset[5].index is invalid");

        validateApprovalRule(vault, contracts.SLISBNB(), contracts.STAKER_GATEWAY());
        validateStakingRule(vault, contracts.STAKER_GATEWAY(), contracts.SLISBNB());

        assertFalse(vault.paused());

        _verifyDefaultRoles(vault);
        _verifyTemporaryRoles(vault);
    }
}
