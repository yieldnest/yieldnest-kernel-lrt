// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

interface IEnzoNetwork {
    /**
     * @notice Deposits tokens into a strategy
     * @param _strategy Address of the strategy to deposit into
     * @param _token Address of the token to deposit
     * @param _amount Amount of tokens to deposit
     */
    function deposit(address _strategy, address _token, uint256 _amount) external;

    /**
     * @notice Adds strategies to the whitelist
     * @param _strategies Array of strategy addresses to whitelist
     */
    function addStrategyWhitelisted(address[] calldata _strategies) external;

    /**
     * @notice Checks if a strategy is whitelisted
     * @param _strategy Address of the strategy to check
     * @return True if the strategy is whitelisted, false otherwise
     */
    function isWhitelisted(address _strategy) external view returns (bool);

    /**
     * @notice Returns the address of the DAO
     * @return Address of the DAO
     */
    function dao() external view returns (address);

    /**
     * @notice Checks if the network is paused
     * @return True if the network is paused, false otherwise
     */
    function paused() external view returns (bool);

    /**
     * @notice Unpauses the network
     * @dev Can only be called by authorized addresses
     */
    function unpause() external;
}
