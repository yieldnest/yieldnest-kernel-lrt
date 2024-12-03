// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IProvider} from "src/interface/IProvider.sol";

contract KernelRateProvider is IProvider {
    error UnsupportedAsset(address asset);

    function getRate(address asset) external view returns (uint256) {
        //TODO get that rate
        return 1;
    }
}
