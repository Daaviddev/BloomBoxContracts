// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IWhitelist.sol";
import "./interfaces/INectar.sol";

contract Vault is Initializable {
    IWhitelist public whitelist;
    INectar internal nectar;

    /**
     * @notice - This contract is the one receiving tokens
     */ 
    // TODO - If this contract is used as a treasury it does not need to receive $NCTR but $USDC.e
    //      - If used as a treasury it also needs to be Ownable
    //      - If not, does it need to have a mapping of balances?
    function initialize(address _nectar, address _whitelist)
        external
        initializer
    {
        whitelist = IWhitelist(_whitelist);
        nectar = INectar(_nectar);
    }

    function withdraw(uint256 _amount) public {
        if (whitelist.isWhitelisted(msg.sender)) {
            require(nectar.transfer(msg.sender, _amount), "transfer failed");
        } else {
            revert("not whitelisted");
        }
    }
}
