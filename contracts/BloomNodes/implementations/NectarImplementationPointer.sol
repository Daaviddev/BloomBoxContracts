// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/INectar.sol";

abstract contract NectarImplementationPointer is Ownable {
    INectar internal nectar;

    event UpdateNectar(
        address indexed oldImplementation,
        address indexed newImplementation
    );

    modifier onlyNectar() {
        require(
            address(nectar) != address(0),
            "Implementations: Nectar is not set"
        );
        address sender = _msgSender();
        require(
            sender == address(nectar),
            "Implementations: Not Nectar"
        );
        _;
    }

    function getNectarImplementation() public view returns (address) {
        return address(nectar);
    }

    function changeNectarImplementation(address newImplementation)
        public
        virtual
        onlyOwner
    {
        address oldImplementation = address(nectar);
        require(
            Address.isContract(newImplementation) ||
                newImplementation == address(0),
            "Nectar: You can only set 0x0 or a contract address as a new implementation"
        );
        nectar = INectar(newImplementation);
        emit UpdateNectar(oldImplementation, newImplementation);
    }

    uint256[49] private __gap;
}