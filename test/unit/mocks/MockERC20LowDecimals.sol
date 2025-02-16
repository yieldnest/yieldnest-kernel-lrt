// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ERC20} from "lib/yieldnest-vault/src/Common.sol";

contract MockERC20LowDecimals is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(msg.sender, 1000000 * (10 ** uint256(decimals())));
    }

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 8;
    }
}
