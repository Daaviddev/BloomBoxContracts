// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./interfaces/IJoeRouter.sol";
import "./interfaces/IJoeFactory.sol";
import "./interfaces/IJoePair.sol";

contract Router {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external pure returns (bool) {
        return true;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external pure returns (uint256[] memory amounts) {
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 0;
        _amounts[1] = 20000;
        return _amounts;
    }

    // fetches and sorts the reserves for a pair
    function getReserves()
        external
        pure
        returns (uint256 reserveA, uint256 reserveB)
    {
        reserveA = 200000 ether;
        reserveB = 20000 ether;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut) {
        require(amountIn > 0, "JoeLibrary: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "JoeLibrary: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn * (997);
        uint256 numerator = amountInWithFee * (reserveOut);
        uint256 denominator = (reserveIn * (1000)) + (amountInWithFee);
        amountOut = numerator / denominator;
    }

    // // returns sorted token addresses, used to handle return values from pairs sorted in this order
    // function sortTokens(address tokenA, address tokenB)
    //     internal
    //     pure
    //     returns (address token0, address token1)
    // {
    //     require(tokenA != tokenB, "JoeLibrary: IDENTICAL_ADDRESSES");
    //     (token0, token1) = tokenA < tokenB
    //         ? (tokenA, tokenB)
    //         : (tokenB, tokenA);
    //     require(token0 != address(0), "JoeLibrary: ZERO_ADDRESS");
    // }

    // // calculates the CREATE2 address for a pair without making any external calls
    // function pairFor(
    //     address factory,
    //     address tokenA,
    //     address tokenB
    // ) internal pure returns (address pair) {
    //     (address token0, address token1) = sortTokens(tokenA, tokenB);
    //     pair = address(
    //         uint256(
    //             keccak256(
    //                 abi.encodePacked(
    //                     hex"ff",
    //                     factory,
    //                     keccak256(abi.encodePacked(token0, token1)),
    //                     hex"0bbca9af0511ad1a1da383135cf3a8d2ac620e549ef9f6ae3a4c33c2fed0af91"
    //                 )
    //             )
    //         )
    //     );
    // }

    // // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    // function quote(
    //     uint256 amountA,
    //     uint256 reserveA,
    //     uint256 reserveB
    // ) internal pure returns (uint256 amountB) {
    //     require(amountA > 0, "JoeLibrary: INSUFFICIENT_AMOUNT");
    //     require(
    //         reserveA > 0 && reserveB > 0,
    //         "JoeLibrary: INSUFFICIENT_LIQUIDITY"
    //     );
    //     amountB = (amountA * (reserveB)) / reserveA;
    // }

    // // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    // function getAmountIn(
    //     uint256 amountOut,
    //     uint256 reserveIn,
    //     uint256 reserveOut
    // ) internal pure returns (uint256 amountIn) {
    //     require(amountOut > 0, "JoeLibrary: INSUFFICIENT_OUTPUT_AMOUNT");
    //     require(
    //         reserveIn > 0 && reserveOut > 0,
    //         "JoeLibrary: INSUFFICIENT_LIQUIDITY"
    //     );
    //     uint256 numerator = (reserveIn * (amountOut)) * (1000);
    //     uint256 denominator = reserveOut - ((amountOut) * (997));
    //     amountIn = (numerator / denominator) + 1;
    // }

    // // performs chained getAmountOut calculations on any number of pairs
    // function getAmountsOut(
    //     address factory,
    //     uint256 amountIn,
    //     address[] memory path
    // ) internal view returns (uint256[] memory amounts) {
    //     require(path.length >= 2, "JoeLibrary: INVALID_PATH");
    //     amounts = new uint256[](path.length);
    //     amounts[0] = amountIn;
    //     for (uint256 i; i < path.length - 1; i++) {
    //         (uint256 reserveIn, uint256 reserveOut) = getReserves(
    //             factory,
    //             path[i],
    //             path[i + 1]
    //         );
    //         amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
    //     }
    // }

    // // performs chained getAmountIn calculations on any number of pairs
    // function getAmountsIn(
    //     address factory,
    //     uint256 amountOut,
    //     address[] memory path
    // ) internal view returns (uint256[] memory amounts) {
    //     require(path.length >= 2, "JoeLibrary: INVALID_PATH");
    //     amounts = new uint256[](path.length);
    //     amounts[amounts.length - 1] = amountOut;
    //     for (uint256 i = path.length - 1; i > 0; i--) {
    //         (uint256 reserveIn, uint256 reserveOut) = getReserves(
    //             factory,
    //             path[i - 1],
    //             path[i]
    //         );
    //         amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
    //     }
    // }
}
