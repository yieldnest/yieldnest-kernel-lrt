// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";

import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

import {ISolvBTCYieldToken} from "src/interface/external/solv/ISolvBTCYieldToken.sol";
import {BTCRateProvider} from "src/module/BTCRateProvider.sol";

contract BTCProviderTest is Test {
    BTCRateProvider public provider;

    function setUp() public {
        provider = new BTCRateProvider();
    }

    function test_Provider_GetRateBTCB() public view {
        uint256 rate = provider.getRate(MC.BTCB);
        assertEq(rate, 1e18, "Rate for BTCB should be 1e18");
    }

    function test_Provider_GetRateSolvBTC() public view {
        uint256 rate = provider.getRate(MC.SOLVBTC);
        assertEq(rate, 1e18, "Rate for SolvBTC should be 1e18");
    }

    function test_Provider_GetRateSolvBTC_BNN() public view {
        uint256 rate = provider.getRate(MC.SOLVBTC_BNN);
        uint256 expected = ISolvBTCYieldToken(MC.SOLVBTC_BNN).getValueByShares(1e18);

        assertEq(rate, expected, "Rate for SolvBTC BNN should be correct");
    }

    function test_Provider_GetRateKernelVault() public view {
        address kernelBTCBVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.BTCB);
        uint256 rate = provider.getRate(kernelBTCBVault);
        assertEq(rate, 1e18, "Rate for Kernel BTCB Vault should be 1e18");

        address kernelBTCxVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.SOLVBTC);
        rate = provider.getRate(kernelBTCxVault);
        assertEq(rate, 1e18, "Rate for Kernel BTCx Vault should be 1e18");
    }

    function test_Provider_UnsupportedAsset() public {
        address unsupportedAsset = address(0x123);
        vm.expectRevert();
        provider.getRate(unsupportedAsset);
    }
}
