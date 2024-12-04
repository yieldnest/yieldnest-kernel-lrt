// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";

import {MockBNBxStakeManagerV2} from "lib/yieldnest-vault/test/unit/mocks/MockBNBxStakeManagerV2.sol";
import {MockSTETH} from "lib/yieldnest-vault/test/unit/mocks/MockST_ETH.sol";

import {MockSlisBnbStakeManager} from "lib/yieldnest-vault/test/unit/mocks/MockSlisBnbStakeManager.sol";
import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {KernelRateProvider} from "src/module/KernelRateProvider.sol";

contract EtchUtils is Test {
    function mockAll() public {
        mockWBNB();
        mockSLISBNB();
        mockBNBX();
        mockProvider();
        mockBnbxStakeManager();
        mockSlisBnbStakeManager();
    }

    function mockWBNB() public {
        WETH9 wbnb = new WETH9();
        bytes memory code = address(wbnb).code;
        vm.etch(MC.WBNB, code);
    }

    function mockSLISBNB() public {
        MockSTETH slisbnb = new MockSTETH();
        bytes memory code = address(slisbnb).code;
        vm.etch(MC.SLISBNB, code);
    }

    function mockBNBX() public {
        WETH9 bnbx = new WETH9();
        bytes memory code = address(bnbx).code;
        vm.etch(MC.BNBX, code);
    }

    function mockProvider() public {
        KernelRateProvider provider = new KernelRateProvider();
        bytes memory code = address(provider).code;
        vm.etch(MC.PROVIDER, code);
    }

    function mockBnbxStakeManager() public {
        MockBNBxStakeManagerV2 bnbxStakeManager = new MockBNBxStakeManagerV2();
        bytes memory code = address(bnbxStakeManager).code;
        vm.etch(MC.BNBX_STAKE_MANAGER, code);
    }

    function mockSlisBnbStakeManager() public {
        MockSlisBnbStakeManager slisBnbStakeManager = new MockSlisBnbStakeManager();
        bytes memory code = address(slisBnbStakeManager).code;
        vm.etch(MC.SLIS_BNB_STAKE_MANAGER, code);
    }
}
