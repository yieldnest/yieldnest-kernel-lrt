// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";
import {IKernelActors, MainnetKernelActors, TestnetKernelActors} from "script/KernelActors.sol";
import {VaultKernelUtils} from "script/VaultKernelUtils.sol";

import {Script} from "lib/forge-std/src/Script.sol";
import {BaseScript, IActors} from "lib/yieldnest-vault/script/BaseScript.sol";

import {KernelClisStrategy} from "src/KernelClisStrategy.sol";
import {KernelStrategy} from "src/KernelStrategy.sol";
import {KernelVaultViewer} from "src/utils/KernelVaultViewer.sol";

contract DeployStrategies is Script, VaultKernelUtils {
    function run() public virtual {
        vm.startBroadcast();

        // Deploy Kernel strategy implementation
        address kernelImpl = address(new KernelStrategy());

        // Deploy CLIS strategy implementation
        address clisImpl = address(new KernelClisStrategy());

        vm.stopBroadcast();

        // Store strategy implementations in JSON file
        string memory json = string.concat(
            "{\"KernelStrategy\": \"",
            vm.toString(kernelImpl),
            "\",",
            "\"ClisStrategy\": \"",
            vm.toString(clisImpl),
            "\"}"
        );
        vm.writeFile(string.concat("deployments/strategies-", vm.toString(block.chainid), ".json"), json);
    }
}
