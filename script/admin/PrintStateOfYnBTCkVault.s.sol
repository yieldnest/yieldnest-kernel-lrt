// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IProvider, Vault} from "lib/yieldnest-vault/script/BaseScript.sol";

import {BaseVault} from "lib/yieldnest-vault/src/BaseVault.sol";
import {BaseKernelScript} from "script/BaseKernelScript.sol";
import {BscContracts} from "script/Contracts.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

contract PrintStateOfYnBTCkVault is Script {
    function run() public {
        // Log chain ID
        uint256 chainId = block.chainid;
        console.log("Chain ID:", chainId);

        // Create contracts instance
        BscContracts contracts = new BscContracts();

        // Get the vault address
        address payable vault = payable(0x78839cE14a8213779128Ee4da6D75E1326606A56);

        // Get the vault instance
        KernelStrategy ynBTCkVault = KernelStrategy(vault);

        // Print total assets
        uint256 totalAssets = ynBTCkVault.totalAssets();
        console.log("Total Assets:", totalAssets);

        // Print block number
        uint256 blockNumber = block.number;
        console.log("Block Number:", blockNumber);

        // Calculate and print the rate using convertToAssets
        uint256 oneShare = 1e18; // 1 share with 18 decimals
        uint256 assetsPerShare = ynBTCkVault.convertToAssets(oneShare);
        console.log("Rate (assets per share):", assetsPerShare);

        // Get the asset at index 2
        address solvBTCBNN = contracts.SOLVBTC_BBN();
        BaseVault.AssetParams memory assetParams = ynBTCkVault.getAsset(solvBTCBNN);
        console.log("Asset solvBTC BNN:");
        console.log("  Address:", solvBTCBNN);
        console.log("  Active:", assetParams.active);
        console.log("  Decimals:", assetParams.decimals);
        console.log("  Index:", assetParams.index);

        // Get BTCB asset information
        address btcb = contracts.BTCB();
        BaseVault.AssetParams memory btcbParams = ynBTCkVault.getAsset(btcb);
        console.log("\nAsset BTCB:");
        console.log("  Address:", btcb);
        console.log("  Active:", btcbParams.active);
        console.log("  Decimals:", btcbParams.decimals);
        console.log("  Index:", btcbParams.index);
        
        // Check if BTCB is withdrawable
        bool isWithdrawable = ynBTCkVault.getAssetWithdrawable(btcb);
        console.log("  Withdrawable:", isWithdrawable);
    }
}
