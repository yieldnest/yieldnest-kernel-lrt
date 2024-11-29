// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";

contract SampleTest is Test {
    function test_nothing() public {
        console.log("test_nothing");
    }
}
