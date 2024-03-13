// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/IWalletObserver.sol";

abstract contract WalletObserverImplementationPointer is OwnableUpgradeable {
    IWalletObserver internal walletObserver;

    event UpdateWalletObserver(
        address indexed oldImplementation,
        address indexed newImplementation
    );

    modifier onlyWalletObserver() {
        require(
            address(walletObserver) != address(0),
            "Implementations: WalletObserver is not set"
        );
        address sender = _msgSender();
        require(
            sender == address(walletObserver),
            "Implementations: Not WalletObserver"
        );
        _;
    }

    function getWalletObserverImplementation() public view returns (address) {
        return address(walletObserver);
    }

    function changeWalletObserverImplementation(address newImplementation)
        public
        virtual
        onlyOwner
    {
        address oldImplementation = address(walletObserver);
        require(
            AddressUpgradeable.isContract(newImplementation) ||
                newImplementation == address(0),
            "WalletObserver: You can only set 0x0 or a contract address as a new implementation"
        );
        walletObserver = IWalletObserver(newImplementation);
        emit UpdateWalletObserver(oldImplementation, newImplementation);
    }

    uint256[49] private __gap;
}