// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IWhitelist {
    function isWhitelisted(address _address) external returns (bool);
}
