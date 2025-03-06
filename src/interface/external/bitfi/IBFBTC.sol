// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {IERC20} from "lib/yieldnest-vault/src/Common.sol";

interface IBFBTC is IERC20 {
    function previewDeposit(uint256 amount) external view returns (uint256);
    function deposit(uint256 amount, uint256 minAmount) external;
    function minDepositTokenAmount() external view returns (uint256);
    function currentRatio() external view returns (uint256);
}
