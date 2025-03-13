// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20, IERC20Metadata} from "lib/yieldnest-vault/src/Common.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";
import {IStakerGateway} from "src/interface/external/kernel/IStakerGateway.sol";
import {IEnzoBTC} from "src/interface/external/lorenzo/IEnzoBTC.sol";
import {IEnzoNetwork} from "src/interface/external/lorenzo/IEnzoNetwork.sol";

/**
 * @title TokenUtils
 * @notice Utility library for interacting with protocol assets in tests
 */
contract TokenUtils is Test {
    // Contract references
    address public vault;
    IStakerGateway public stakerGateway;

    /**
     * @notice Constructor to set up contract references
     * @param _vault Address of the vault contract
     * @param _stakerGateway Address of the staker gateway contract
     */
    constructor(address _vault, IStakerGateway _stakerGateway) {
        vault = _vault;
        stakerGateway = _stakerGateway;
    }

    function getBTCB(address bob, uint256 amount) public {
        IERC20 btcb = IERC20(MC.BTCB);
        uint256 beforeBobBTCB = btcb.balanceOf(bob);

        vm.prank(0xF977814e90dA44bFA03b6295A0616a897441aceC);
        btcb.transfer(bob, amount);

        assertEq(btcb.balanceOf(bob), beforeBobBTCB + amount, "Bob's BTCB balance should increase by amount");
    }

    function getEnzoBTC(address bob, uint256 amount) public returns (uint256) {
        IERC20 btcb = IERC20(MC.BTCB);

        address ENZO_NETWORK = 0x7EFb3515d9eC4537FaFCA635a1De7Da7A5C5c567;
        address ENZO_STRATEGY = 0xB3cF78f3e483b63280CFe19D52C9c1bDD03D02aB;

        {
            // Check if the bob address is blacklisted in EnzoBTC
            address ENZOBTC = MC.ENZOBTC;

            // Get the blacklist admin from EnzoBTC
            address blacklistAdmin = IEnzoBTC(ENZOBTC).blackListAdmin();

            // Check if the kernel gateway vault for Enzo is blacklisted
            address kernelGatewayVault = stakerGateway.getVault(ENZOBTC);
            if (IEnzoBTC(ENZOBTC).isBlackListed(kernelGatewayVault)) {
                // Remove kernel gateway vault from the blacklist
                vm.prank(blacklistAdmin);
                IEnzoBTC(ENZOBTC).removeBlackList(kernelGatewayVault);
            }

            // Also check if the kernel strategy is blacklisted
            address kernelStrategy = address(vault);
            if (IEnzoBTC(ENZOBTC).isBlackListed(kernelStrategy)) {
                // Remove kernel strategy from the blacklist
                vm.prank(blacklistAdmin);
                IEnzoBTC(ENZOBTC).removeBlackList(kernelStrategy);
            }
        }

        // Check if the strategy is whitelisted in Enzo Network
        // If not, add it to the whitelist
        if (!IEnzoNetwork(ENZO_NETWORK).isWhitelisted(ENZO_STRATEGY)) {
            address[] memory strategies = new address[](1);
            strategies[0] = ENZO_STRATEGY;

            // Need to be called by an admin of Enzo Network
            // This is a test environment, so we can use vm.prank
            vm.prank(IEnzoNetwork(ENZO_NETWORK).dao()); // Prank as the Enzo Network DAO
            IEnzoNetwork(ENZO_NETWORK).addStrategyWhitelisted(strategies);
        }

        // Check if Enzo Network is paused and unpause it if necessary
        if (IEnzoNetwork(ENZO_NETWORK).paused()) {
            // Need to be called by an admin of Enzo Network
            vm.prank(IEnzoNetwork(ENZO_NETWORK).dao()); // Prank as the Enzo Network DAO
            IEnzoNetwork(ENZO_NETWORK).unpause();
        }

        // Get BTCB first
        getBTCB(bob, amount + 1 ether);

        // Approve BTCB spend
        vm.prank(bob);
        btcb.approve(ENZO_NETWORK, amount + 1 ether);

        // Approve BTCB spend to strategy
        vm.prank(bob);
        btcb.approve(ENZO_STRATEGY, amount + 1 ether);
        // Deposit BTCB to get enzoBTC
        vm.prank(bob);
        IEnzoNetwork(ENZO_NETWORK).deposit(ENZO_STRATEGY, address(MC.ENZOBTC), amount);

        // BTCB has 18 decimals, enzoBTC has 8 decimals
        uint256 decimalsFrom = IERC20Metadata(MC.BTCB).decimals();
        uint256 decimalsTo = IERC20Metadata(MC.ENZOBTC).decimals();
        uint256 expectedEnzoBTC = amount / 10 ** (decimalsFrom - decimalsTo); // Adjust for decimal difference

        uint256 actualEnzoBTC = IERC20(MC.ENZOBTC).balanceOf(bob);
        assertEq(actualEnzoBTC, expectedEnzoBTC, "Bob should have received the correct amount of enzoBTC");
        assertEq(expectedEnzoBTC, amount / 10 ** 10, "Expected enzoBTC should be amount divided by 10^10");
        return actualEnzoBTC;
    }
}
