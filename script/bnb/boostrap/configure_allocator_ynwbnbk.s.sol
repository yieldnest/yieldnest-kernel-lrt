// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {console} from "lib/forge-std/src/console.sol";
import {BaseKernelScript} from "script/BaseKernelScript.sol";

// FOUNDRY_PROFILE=mainnet forge script ConfigureAllocatorYnWBNBk --sender 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract ConfigureAllocatorYnWBNBk is BaseKernelScript {
    function symbol() public pure override returns (string memory) {
        return "ynWBNBk";
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
