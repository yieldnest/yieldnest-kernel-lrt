// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

interface IEnzoBTC {
    /**
     * @notice Returns the address of the blacklist admin
     * @return Address of the blacklist admin
     */
    function blackListAdmin() external view returns (address);
    /**
     * @notice Checks if an address is blacklisted
     * @param _address Address to check
     * @return True if the address is blacklisted, false otherwise
     */
    function isBlackListed(address _address) external view returns (bool);

    /**
     * @notice Removes an address from the blacklist
     * @param _clearedUser Address to remove from the blacklist
     */
    function removeBlackList(address _clearedUser) external;
}
