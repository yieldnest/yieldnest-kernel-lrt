/* solhint-disable no-console, max-line-length, quotes */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// @dev picked up from https://github.com/ind-igo/forge-safe
// @dev modified to work with our script setup

// 🧩 MODULES
import {Script, console, stdJson} from "lib/forge-std/src/Script.sol";

// ⭐️ SCRIPT
abstract contract BatchScript is Script {
    using stdJson for string;

    address private constant SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;

    // Chain ID, configured by chain.
    uint256 private chainId;

    // Address to send transaction from
    address private safe;

    enum Operation {
        CALL,
        DELEGATECALL
    }

    bytes[] public encodedTxns;

    // Modifiers

    modifier isBatch(address safe_) {
        // Store the provided safe address
        safe = safe_;

        // Run batch
        _;
    }

    // Functions to consume in a script

    // Adds an encoded transaction to the batch.
    // Encodes the transaction as packed bytes of:
    // - `operation` as a `uint8` with `0` for a `call` or `1` for a `delegatecall` (=> 1 byte),
    // - `to` as an `address` (=> 20 bytes),
    // - `value` as in msg.value, sent as a `uint256` (=> 32 bytes),
    // -  length of `data` as a `uint256` (=> 32 bytes),
    // - `data` as `bytes`.
    function addToBatch(address to_, uint256 value_, bytes memory data_) internal returns (bytes memory) {
        // Add transaction to batch array
        encodedTxns.push(abi.encodePacked(Operation.CALL, to_, value_, data_.length, data_));

        // Simulate transaction and get return value
        vm.prank(safe);
        (bool success, bytes memory data) = to_.call{value: value_}(data_);
        if (success) {
            return data;
        } else {
            revert(string(data));
        }
    }

    function displayBatch() internal view {
        // Set initial batch fields
        address to = SAFE_MULTISEND_ADDRESS;
        uint256 value = 0;
        Operation operation = Operation.DELEGATECALL;

        // Encode the batch calldata. The list of transactions is tightly packed.
        bytes memory data;
        uint256 len = encodedTxns.length;
        for (uint256 i; i < len; ++i) {
            data = bytes.concat(data, encodedTxns[i]);
        }
        bytes memory txData = abi.encodeWithSignature("multiSend(bytes)", data);

        console.log("");
        console.log("Safe Batch Transaction:");
        console.log("To: ", to);
        console.log("Operation: %d (%s)", uint256(operation), "DELEGATECALL");
        console.log("Value: ", value);
        console.log("Data: ");
        console.logBytes(txData);
        console.log("");
    }

}
