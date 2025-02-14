// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider, Vault} from "lib/yieldnest-vault/script/BaseScript.sol";

import {KernelStrategy} from "src/KernelStrategy.sol";
import {BTCRateProvider} from "src/module/BTCRateProvider.sol";
import {TestnetBTCRateProvider} from "test/module/BTCRateProvider.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {console} from "lib/forge-std/src/console.sol";
import {FeeMath} from "lib/yieldnest-vault/src/module/FeeMath.sol";
import {BaseKernelScript} from "script/BaseKernelScript.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";

// FOUNDRY_PROFILE=mainnet forge script DeployBTCRateProvider --sender 0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a
contract DeployBTCRateProvider is BaseKernelScript {
    function symbol() public pure override returns (string memory) {
        return "ynBTCk";
    }

    function deployRateProvider() internal {
        if (block.chainid == 97) {
            rateProvider = IProvider(address(new TestnetBTCRateProvider()));
        }

        if (block.chainid == 56) {
            rateProvider = IProvider(address(new BTCRateProvider()));
        }
    }

    function run() public {
        vm.startBroadcast();

        deployRateProvider();

        console.log("Rate Provider deployed at:", address(rateProvider));

        vm.stopBroadcast();
    }
}
