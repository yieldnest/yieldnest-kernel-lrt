// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";

import {Test} from "lib/forge-std/src/Test.sol";

import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {MockSTETH} from "lib/yieldnest-vault/test/unit/mocks/MockST_ETH.sol";
import {MockYNETH} from "lib/yieldnest-vault/test/unit/mocks/MockYNETH.sol";
import {MockCL_STETH} from "lib/yieldnest-vault/test/unit/mocks/MockCL_STETH.sol";
import {MockYNLSDE} from "lib/yieldnest-vault/test/unit/mocks/MockYNLSDE.sol";
import {KernelRateProvider} from "src/module/KernelRateProvider.sol";
import {MockBuffer} from "lib/yieldnest-vault/test/unit/mocks/MockBuffer.sol";
import {MockBNBxStakeManagerV2} from "lib/yieldnest-vault/test/unit/mocks/MockBNBxStakeManagerV2.sol";
import {MockSlisBnbStakeManager} from "lib/yieldnest-vault/test/unit/mocks/MockSlisBnbStakeManager.sol";

contract EtchUtils is Test {
    function mockAll() public {
        mockWETH9();
        mockStETH();
        mockRETH();
        mockYNETH();
        mockProvider();
        mockBnbxStakeManager();
        mockSlisBnbStakeManager();
    }

    function mockWETH9() public {
        WETH9 weth = new WETH9();
        bytes memory code = address(weth).code;
        vm.etch(MainnetContracts.WETH, code);
    }

    function mockStETH() public {
        MockSTETH steth = new MockSTETH();
        bytes memory code = address(steth).code;
        vm.etch(MainnetContracts.STETH, code);
    }

    function mockRETH() public {
        WETH9 reth = new WETH9();
        bytes memory code = address(reth).code;
        vm.etch(MainnetContracts.RETH, code);
    }

    function mockYNETH() public {
        MockYNETH yneth = new MockYNETH();
        bytes memory code = address(yneth).code;
        vm.etch(MainnetContracts.YNETH, code);
    }

    function mockProvider() public {
        KernelRateProvider provider = new KernelRateProvider();
        bytes memory code = address(provider).code;
        vm.etch(MainnetContracts.PROVIDER, code);
    }

    function mockBnbxStakeManager() public {
        MockBNBxStakeManagerV2 bnbxStakeManager = new MockBNBxStakeManagerV2();
        bytes memory code = address(bnbxStakeManager).code;
        vm.etch(MainnetContracts.BNBX_STAKE_MANAGER, code);
    }

    function mockSlisBnbStakeManager() public {
        MockSlisBnbStakeManager slisBnbStakeManager = new MockSlisBnbStakeManager();
        bytes memory code = address(slisBnbStakeManager).code;
        vm.etch(MainnetContracts.SLIS_BNB_STAKE_MANAGER, code);
    }
}
