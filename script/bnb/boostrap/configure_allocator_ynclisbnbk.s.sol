// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {console} from "lib/forge-std/src/console.sol";
import {BaseKernelScript} from "script/BaseKernelScript.sol";

/**
 * @notice This script configures the allocator role for the ynCLISBNBk vault
 * @dev It performs the following steps:
 * 1. Loads deployment info and sets up environment variables based on chain (testnet vs mainnet)
 * 2. Verifies that YNBNBx (the allocator) is deployed by checking its address is not zero
 * 3. Grants the ALLOCATOR_ROLE to YNBNBx, allowing it to manage allocations for the vault
 * 4. Renounces the DEFAULT_ADMIN_ROLE from the deployer, removing admin privileges
 *
 * This is a one-time setup script that configures the vault's permissions and removes admin access
 */

// FOUNDRY_PROFILE=mainnet forge script ConfigureAllocatorYnCLISBNBk --sender 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract ConfigureAllocatorYnCLISBNBk is BaseKernelScript {
    function symbol() public pure override returns (string memory) {
        return "ynCLISBNBk";
    }

    function run() public {
        _loadDeployment();
        _setup();

        console.log("YNBNBx address:", contracts.YNBNBX());

        // Verify YNBNBx is deployed
        require(contracts.YNBNBX() != address(0), "YNBNBx not deployed");

        vm.startBroadcast();

        // Set YNBNBx as allocator
        vault_.grantRole(vault_.ALLOCATOR_ROLE(), contracts.YNBNBX());

        // Renounce admin role
        vault_.renounceRole(vault_.DEFAULT_ADMIN_ROLE(), msg.sender);

        vm.stopBroadcast();
    }
}
