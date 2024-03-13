// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract USDC is ERC20Upgradeable {
    function init() external initializer {
        __ERC20_init("USD Coin", "USDC.e");
        _mint(_msgSender(), 30000 ether);
    }
}
