// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";

import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {ISolvBTCYieldToken} from "src/interface/external/solv/ISolvBTCYieldToken.sol";
import {CoBTCRateProvider} from "src/module/CoBTCRateProvider.sol";

contract CoBTCProviderTest is Test {
    CoBTCRateProvider public provider;

    function setUp() public {
        provider = new CoBTCRateProvider();
    }

    function test_Provider_GetRateCoBTC() public view {
        uint256 rate = provider.getRate(MC.COBTC);
        assertEq(rate, 1e8, "Rate for CoBTC should be 1e8");
    }
}
