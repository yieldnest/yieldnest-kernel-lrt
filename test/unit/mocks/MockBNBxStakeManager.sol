// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IBNBXStakeManagerV2} from "lib/yieldnest-vault/src/interface/external/stader/IBNBXStakeManagerV2.sol";

contract MockBNBxStakeManager is IBNBXStakeManagerV2 {
    function convertBnbToBnbX(uint256 amount) external pure returns (uint256) {
        return amount * 2;
    }

    function convertBnbXToBnb(uint256 amount) external pure returns (uint256) {
        return amount / 2;
    }
}
