// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./IJoeRouter.sol";
import "./IJoeFactory.sol";
import "./IJoePair.sol";

interface IMiniRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external pure returns (bool);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external pure returns (uint256[] memory);

    function getReserves()
        external
        pure
        returns (uint256 reserveOut, uint256 reserveIn);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);
}
