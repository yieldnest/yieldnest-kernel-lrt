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
}
