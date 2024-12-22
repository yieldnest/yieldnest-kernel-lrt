/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IActors} from "lib/yieldnest-vault/script/Actors.sol";

interface IKernelActors is IActors {
    function ADMIN() external view returns (address);
    function UNAUTHORIZED() external view returns (address);
    function PROPOSER_1() external view returns (address);
    function PROPOSER_2() external view returns (address);
    function EXECUTOR_1() external view returns (address);
    function EXECUTOR_2() external view returns (address);

    /// @dev timelock
    function FEE_MANAGER() external view returns (address);
    /// @dev timelock
    function PROVIDER_MANAGER() external view returns (address);
    /// @dev timelock
    function BUFFER_MANAGER() external view returns (address);
    /// @dev timelock
    function ASSET_MANAGER() external view returns (address);
    /// @dev timelock
    function PROCESSOR_MANAGER() external view returns (address);
    /// @dev processor
    function PROCESSOR() external view returns (address);
    /// @dev multisig
    function PAUSER() external view returns (address);
    /// @dev multisig
    function UNPAUSER() external view returns (address);
    /// @dev timelock
    function KERNEL_DEPENDENCY_MANAGER() external view returns (address);
    /// @dev multisig
    function DEPOSIT_MANAGER() external view returns (address);
    /// @dev multisig
    function ALLOCATOR_MANAGER() external view returns (address);
}

contract BscActors is IKernelActors {
    // Multisigs
    // solhint-disable-next-line const-name-snakecase
    address private constant YnSecurityCouncil = 0x721688652DEa9Cabec70BD99411EAEAB9485d436;

    // Roles
    address public constant ADMIN = YnSecurityCouncil;
    address public constant UNAUTHORIZED = address(0);
    address public constant PROCESSOR = 0x258d7614d9c608D191A8a103f95B7Df066a19bbF;
    address public constant EXECUTOR_1 = YnSecurityCouncil;
    address public constant PROPOSER_1 = YnSecurityCouncil;
    address public constant EXECUTOR_2 = YnSecurityCouncil;
    address public constant PROPOSER_2 = YnSecurityCouncil;

    address public constant FEE_MANAGER = YnSecurityCouncil;
    address public constant PROVIDER_MANAGER = YnSecurityCouncil;
    address public constant BUFFER_MANAGER = YnSecurityCouncil;
    address public constant ASSET_MANAGER = YnSecurityCouncil;
    address public constant PROCESSOR_MANAGER = YnSecurityCouncil;
    address public constant PAUSER = 0x7B4B43f00cf80AABda8F72d61b129F1e7F86fCaF;
    address public constant UNPAUSER = YnSecurityCouncil;

    address public constant KERNEL_DEPENDENCY_MANAGER = YnSecurityCouncil;
    address public constant DEPOSIT_MANAGER = YnSecurityCouncil;
    address public constant ALLOCATOR_MANAGER = YnSecurityCouncil;
}

contract ChapelActors is IKernelActors {
    address public constant ADMIN = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant UNAUTHORIZED = address(0);

    address public constant PROPOSER_1 = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant PROPOSER_2 = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;

    address public constant EXECUTOR_1 = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant EXECUTOR_2 = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;

    address public constant FEE_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant PROVIDER_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant BUFFER_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant ASSET_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant PROCESSOR_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant PROCESSOR = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant PAUSER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant UNPAUSER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;

    address public constant KERNEL_DEPENDENCY_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant DEPOSIT_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant ALLOCATOR_MANAGER = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
}
