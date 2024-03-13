// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface INectar is IERC20 {
    function owner() external view returns (address);

    function burnNectar(address account, uint256 amount) external;

    function mintNectar(address account, uint256 amount) external;

    function liquidityReward(uint256 amount) external;

    function _transfer(address from, address to, uint256 amount) external;
}