/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IContracts {
    function WBNB() external view returns (address);
    function SLISBNB() external view returns (address);
    function BNBX() external view returns (address);

    function YNBNBK() external view returns (address);

    function YNBNBX() external view returns (address);
    function YNBTCX() external view returns (address);

    function STAKER_GATEWAY() external view returns (address);
    function CLISBNB() external view returns (address);
    function BTCB() external view returns (address);
    function SOLVBTC() external view returns (address);
    function SOLVBTC_BBN() external view returns (address);
}

library MainnetContracts {
    // tokens
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant SLISBNB = 0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B;
    address public constant BNBX = 0x1bdd3Cf7F79cfB8EdbB955f20ad99211551BA275;
    address public constant CLISBNB = 0x4b30fcAA7945fE9fDEFD2895aae539ba102Ed6F6;

    // btc tokens
    address public constant BTCB = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;
    address public constant SOLVBTC = 0x4aae823a6a0b376De6A78e74eCC5b079d38cBCf7;
    address public constant SOLVBTC_BBN = 0x1346b618dC92810EC74163e4c27004c921D446a5;

    // stake managers
    address public constant BNBX_STAKE_MANAGER = 0x3b961e83400D51e6E1AF5c450d3C7d7b80588d28;
    address public constant SLIS_BNB_STAKE_MANAGER = 0x1adB950d8bB3dA4bE104211D5AB038628e477fE6;

    // BNB max vault
    address public constant YNBNBX = 0x32C830f5c34122C6afB8aE87ABA541B7900a2C5F;

    // bnb vault
    address public constant YNBNBK = 0x304B5845b9114182ECb4495Be4C91a273b74B509;
    address public constant YNWBNBK = 0x6EC6b7F106674d6D82b7b24446C7ebaf349d59A1;
    address public constant YNCLISBNBK = 0x03276919F8b6eE37BA8EE4ee68a1c5f48b667834;

    // btc vault
    address public constant YNBTCK = 0x78839cE14a8213779128Ee4da6D75E1326606A56;

    // kernel
    address public constant STAKER_GATEWAY = 0xb32dF5B33dBCCA60437EC17b27842c12bFE83394;
    address public constant KERNEL_CONFIG = 0x45d7Bb73253A908E6160aa5FD9DA083F7Bc6faf5;
    address public constant KERNEL_CONFIG_ADMIN = 0x40f5f0f5E78289B33E450fBCA1cbD8700098cd23;
    address public constant ASSET_REGISTRY = 0xd0B91Fc0a323bbb726faAF8867CdB1cA98c44ABB;

    address public constant PROVIDER = address(123456789); // TODO: Update with deployed Provider
    address public constant BUFFER = address(987654321); // TODO: Update with deployed buffer
}

library TestnetContracts {
    // tokens
    address public constant WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    address public constant SLISBNB = 0xCc752dC4ae72386986d011c2B485be0DAd98C744;
    address public constant BNBX = 0x6cd3f51A92d022030d6e75760200c051caA7152A;
    address public constant CLISBNB = address(0);

    // btc tokens
    address public constant BTCB = 0x6ce8dA28E2f864420840cF74474eFf5fD80E65B8;
    address public constant SOLVBTC = 0x1cF0e51005971c5B78b4A8feE419832CFCCD8cf9;
    address public constant SOLVBTC_BBN = 0xB4618618b6Fcb61b72feD991AdcC344f43EE57Ad;

    // stake managers
    address public constant BNBX_STAKE_MANAGER = address(0);
    address public constant SLIS_BNB_STAKE_MANAGER = address(0);

    address public constant YNBNBX = 0x6164f96Fa28147508d3545c38B61eD0BD7c5DF03;
    // bnb vault
    address public constant YNBNBK = 0x7e87787C22117374Fad2E3E2E8C6159f0875F92e;

    address public constant STAKER_GATEWAY = 0x1A42ff0BA795F6d63A7F0060809F85A794E9f1Ae;
    address public constant KERNEL_CONFIG = 0x4847C1E3683295f6ACa2e4f17Fe35d9Cd35b3FcB;
    address public constant KERNEL_CONFIG_ADMIN = 0xea69CCFe55Be6e68Af1164B8da2E23cF5f62808c;
    address public constant ASSET_REGISTRY = 0xb63809662374ce93FC05d18Bd60c17d3eF184203;

    address public constant PROVIDER = address(123456789);
    address public constant BUFFER = address(987654321);
}

contract ChapelContracts is IContracts {
    function WBNB() external pure override returns (address) {
        return TestnetContracts.WBNB;
    }

    function SLISBNB() external pure override returns (address) {
        return TestnetContracts.SLISBNB;
    }

    function BNBX() external pure override returns (address) {
        return TestnetContracts.BNBX;
    }

    function YNBNBK() external pure override returns (address) {
        return TestnetContracts.YNBNBK;
    }

    // TODO: Update with deployed YNBNBX
    function YNBNBX() external pure override returns (address) {
        return TestnetContracts.YNBNBX;
    }

    function YNBTCX() external pure override returns (address) {
        return address(0);
    }

    function STAKER_GATEWAY() external pure override returns (address) {
        return TestnetContracts.STAKER_GATEWAY;
    }

    function CLISBNB() external pure override returns (address) {
        return TestnetContracts.CLISBNB;
    }

    function BTCB() external pure override returns (address) {
        return TestnetContracts.BTCB;
    }

    function SOLVBTC() external pure override returns (address) {
        return TestnetContracts.SOLVBTC;
    }

    function SOLVBTC_BBN() external pure override returns (address) {
        return TestnetContracts.SOLVBTC_BBN;
    }
}

contract BscContracts is IContracts {
    function WBNB() external pure override returns (address) {
        return MainnetContracts.WBNB;
    }

    function SLISBNB() external pure override returns (address) {
        return MainnetContracts.SLISBNB;
    }

    function BNBX() external pure override returns (address) {
        return MainnetContracts.BNBX;
    }

    function YNBTCX() external pure override returns (address) {
        return address(0);
    }

    function YNBNBK() external pure override returns (address) {
        return MainnetContracts.YNBNBK;
    }

    // TODO: Update with deployed YNBNBX
    function YNBNBX() external pure override returns (address) {
        return MainnetContracts.YNBNBX;
    }

    function STAKER_GATEWAY() external pure override returns (address) {
        return MainnetContracts.STAKER_GATEWAY;
    }

    function CLISBNB() external pure override returns (address) {
        return MainnetContracts.CLISBNB;
    }

    function BTCB() external pure override returns (address) {
        return MainnetContracts.BTCB;
    }

    function SOLVBTC() external pure override returns (address) {
        return MainnetContracts.SOLVBTC;
    }

    function SOLVBTC_BBN() external pure override returns (address) {
        return MainnetContracts.SOLVBTC_BBN;
    }
}
