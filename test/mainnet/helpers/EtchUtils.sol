// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";

import {Test} from "lib/forge-std/src/Test.sol";

contract EtchUtils is Test {
    function etchProvider(address provider) public {
        bytes memory code = address(provider).code;
        vm.etch(MC.PROVIDER, code);
    }

    function etchBuffer(address buffer) public {
        bytes memory code = address(buffer).code;
        vm.etch(MC.BUFFER, code);
    }
}
