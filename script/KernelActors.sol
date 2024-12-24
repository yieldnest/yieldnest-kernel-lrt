/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IActors, MainnetActors, TestnetActors} from "lib/yieldnest-vault/script/Actors.sol";

interface IKernelActors is IActors {
    /// @dev timelock
    function KERNEL_DEPENDENCY_MANAGER() external view returns (address);
    /// @dev multisig
    function DEPOSIT_MANAGER() external view returns (address);
    /// @dev multisig
    function ALLOCATOR_MANAGER() external view returns (address);
}

contract MainnetKernelActors is MainnetActors, IKernelActors {
    address public constant KERNEL_DEPENDENCY_MANAGER = YnSecurityCouncil;
    address public constant DEPOSIT_MANAGER = YnSecurityCouncil;
    address public constant ALLOCATOR_MANAGER = YnSecurityCouncil;
}

contract TestnetKernelActors is TestnetActors, IKernelActors {
    address public constant KERNEL_DEPENDENCY_MANAGER = YnSecurityCouncil;
    address public constant DEPOSIT_MANAGER = YnSecurityCouncil;
    address public constant ALLOCATOR_MANAGER = YnSecurityCouncil;
}
