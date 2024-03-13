// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/IBloomsManagerUpgradeable.sol";

abstract contract BloomsManagerImplementationPointerUpgradeable is OwnableUpgradeable {
    IBloomsManagerUpgradeable internal bloomsManager;

    event UpdateBloomsManager(
        address indexed oldImplementation,
        address indexed newImplementation
    );

    modifier onlyBloomsManager() {
        require(
            address(bloomsManager) != address(0),
            "Implementations: BloomsManager is not set"
        );
        address sender = _msgSender();
        require(
            sender == address(bloomsManager),
            "Implementations: Not BloomsManager"
        );
        _;
    }

    function getBloomsManagerImplementation() public view returns (address) {
        return address(bloomsManager);
    }

    function changeBloomsManagerImplementation(address newImplementation)
        public
        virtual
        onlyOwner
    {
        address oldImplementation = address(bloomsManager);
        require(
            AddressUpgradeable.isContract(newImplementation) ||
                newImplementation == address(0),
            "BloomsManager: You can only set 0x0 or a contract address as a new implementation"
        );
        bloomsManager = IBloomsManagerUpgradeable(newImplementation);
        emit UpdateBloomsManager(oldImplementation, newImplementation);
    }

    uint256[49] private __gap;
}