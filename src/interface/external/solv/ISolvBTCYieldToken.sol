// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISolvBTCYieldToken {
    function getValueByShares(uint256 shares) external view returns (uint256 value);
    function getSharesByValue(uint256 value) external view returns (uint256 shares);
    function getOracleDecimals() external view returns (uint8);
    function getOracle() external view returns (address);
}
