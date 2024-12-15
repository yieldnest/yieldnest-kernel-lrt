// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";

import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract TransferAssets is Script {
    address public constant TOKEN = 0x6ce8dA28E2f864420840cF74474eFf5fD80E65B8;
    address public constant TO = 0xeF444ABe7cf8fFd94dcBE5e4e1F461C2b4c817E3;
    uint256 public constant AMOUNT = 0.05 ether;

    function run() external {
        // vm.startBroadcast();

        // // Transfer ERC20 tokens
        // IERC20(TOKEN).transfer(TO, AMOUNT);

        // vm.stopBroadcast();

        // Read first storage slot at 0xCc752dC4ae72386986d011c2B485be0DAd98C744
        bytes32 slot0 = vm.load(0xCc752dC4ae72386986d011c2B485be0DAd98C744, bytes32(uint256(1)));
        address value = address(uint160(uint256(slot0)));
        console.log("Value at slot 0:", value);
    }
}
