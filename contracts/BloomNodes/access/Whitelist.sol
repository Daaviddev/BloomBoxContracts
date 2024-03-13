// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IWhitelist.sol";

contract Whitelist is IWhitelist, Initializable, OwnableUpgradeable {
    mapping(address => bool) public isWhitelisted;

    event WhitelistAdded(address addr);
    event WhitelistRemoved(address addr);

    function initialize() external initializer {
        __Ownable_init();
    }

    /**
     * @dev add addresses to the whitelist
     * @param _addrs addresses
     * false if all addresses were already in the whitelist
     */
    function addToWhitelist(address[] memory _addrs) external onlyOwner {
        for (uint256 i = 0; i < _addrs.length; i++) {
            isWhitelisted[_addrs[i]] = true;

            emit WhitelistAdded(_addrs[i]);
        }
    }

    /**
     * @dev remove addresses from the whitelist
     * @param _addrs addresses
     * false if all addresses weren't in the whitelist in the first place
     */
    function removeFromWhitelist(address[] memory _addrs) external onlyOwner {
        for (uint256 i = 0; i < _addrs.length; i++) {
            isWhitelisted[_addrs[i]] = false;

            emit WhitelistRemoved(_addrs[i]);
        }
    }
}
