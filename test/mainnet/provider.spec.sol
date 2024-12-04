// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {IBNBXStakeManagerV2} from "lib/yieldnest-vault/src/interface/external/stader/IBNBXStakeManagerV2.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {IProvider, KernelRateProvider} from "src/module/KernelRateProvider.sol";

contract ProviderTest is Test {
    IProvider public provider;

    function setUp() public {
        provider = IProvider(new KernelRateProvider());
    }

    function test_Provider_GetRateWBNB() public view {
        uint256 rate = provider.getRate(MC.WBNB);
        assertEq(rate, 1e18, "Rate for WBNB should be 1e18");
    }

    function test_Provider_GetRateBNBx() public view {
        uint256 expectedRate = IBNBXStakeManagerV2(MC.BNBX_STAKE_MANAGER).convertBnbXToBnb(1e18);
        uint256 rate = provider.getRate(MC.BNBX);
        assertEq(rate, expectedRate, "Rate for BNBx should match the ratio");
    }

    function test_Provider_GetRateKernelVault() public view {
        address kernelWBNBVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.WBNB);
        uint256 rate = provider.getRate(kernelWBNBVault);
        assertEq(rate, 1e18, "Rate for Kernel WBNB Vault should be 1e18");

        address kernelBNBxVault = IStakerGateway(MC.STAKER_GATEWAY).getVault(MC.BNBX);
        rate = provider.getRate(kernelBNBxVault);
        assertEq(
            rate,
            IBNBXStakeManagerV2(MC.BNBX_STAKE_MANAGER).convertBnbXToBnb(1e18),
            "Rate for Kernel BNBx Vault should match the ratio"
        );
    }

    function test_Provider_UnsupportedAsset() public {
        address unsupportedAsset = address(0x123);
        vm.expectRevert();
        provider.getRate(unsupportedAsset);
    }
}
