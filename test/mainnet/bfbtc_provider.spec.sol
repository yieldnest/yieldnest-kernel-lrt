// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";

import {BfBTCRateProvider} from "src/module/BfBTCRateProvider.sol";

contract BfBTCProviderTest is Test {
    BfBTCRateProvider public provider;

    function setUp() public {
        provider = new BfBTCRateProvider();
    }

    function test_Provider_GetRateBfBTC() public view {
        uint256 rate = provider.getRate(MC.BFBTC);
        assertEq(rate, 1e8, "Rate for BfBTC should be 1e8");
    }
}
