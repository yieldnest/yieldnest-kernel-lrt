// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IWBNB {
    /* External Functions ***********************************************************************************************/

    function deposit() external payable;

    function withdraw(uint256 wad) external;

    function balanceOf(address) external view returns (uint256);
}
