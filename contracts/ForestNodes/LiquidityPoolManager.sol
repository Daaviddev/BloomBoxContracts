// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IJoeRouter.sol";
import "./IJoeFactory.sol";
import "./IJoePair.sol";
import "./ILiquidityPoolManager.sol";
import "./OwnerRecovery.sol";
import "./UniverseImplementationPointer.sol";

contract LiquidityPoolManager is
    Ownable,
    OwnerRecovery,
    UniverseImplementationPointer
{
    using SafeERC20 for IERC20;

    event SwapAndLiquify(
        uint256 indexed half,
        uint256 indexed initialBalance,
        uint256 indexed newRightBalance
    );
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    bool private liquifyEnabled = false;
    bool private isSwapping = false;
    uint256 public swapTokensToLiquidityThreshold;

    // Initial liquidity split settings
    address[] public feeAddresses = [
        address(0x6D9022E827Ec759fC0C9EDf2c79C4D609fb749c5), // Treasury investments (40%)
        address(0x07026bD89E88b742168CA3011931BA324CCa9bfb), // Marketing (30%)
        address(0x1981d1dd51f51f7Ffc16Dd13d69bFFBA942dACCe) // Dev (30%)
    ];
    uint8[] public feePercentages = [40, 30];

    uint256 public pairLiquidityTotalSupply;

    IJoeRouter02 private router;
    IJoePair private pair;
    IERC20 private leftSide;
    IERC20 private rightSide;

    uint256 private constant MAX_UINT256 =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    constructor(
        address _router,
        address[2] memory path,
        uint256 _swapTokensToLiquidityThreshold
    ) {
        require(
            _router != address(0),
            "LiquidityPoolManager: Router cannot be undefined"
        );
        router = IJoeRouter02(_router);

        pair = createPairWith(path);
        leftSide = IERC20(path[0]);
        rightSide = IERC20(path[1]);
        pairLiquidityTotalSupply = pair.totalSupply();

        updateSwapTokensToLiquidityThreshold(_swapTokensToLiquidityThreshold);

        // Left side should be main contract
        changeUniverseImplementation(address(leftSide));

        shouldLiquify(true);
    }

    function afterTokenTransfer(address sender)
        external
        onlyUniverse
        returns (bool)
    {
        uint256 leftSideBalance = leftSide.balanceOf(address(this));
        bool shouldSwap = leftSideBalance >= swapTokensToLiquidityThreshold;
        if (
            shouldSwap &&
            liquifyEnabled &&
            pair.totalSupply() > 0 &&
            !isSwapping &&
            !isPair(sender) &&
            !isRouter(sender)
        ) {
            // This prevents inside calls from triggering this function again (infinite loop)
            // It's ok for this function to be reentrant since it's protected by this check
            isSwapping = true;

            // To prevent bigger sell impact we only sell in batches with the threshold as a limit
            uint256 totalLP = swapAndLiquify(swapTokensToLiquidityThreshold);
            uint256 totalLPRemaining = totalLP;

            for (uint256 i = 0; i < feeAddresses.length; i++) {
                if ((feeAddresses.length - 1) == i) {
                    // Send remaining LP tokens to the last address
                    sendLPTokensTo(feeAddresses[i], totalLPRemaining);
                } else {
                    uint256 calculatedFee = (totalLP * feePercentages[i]) / 100;
                    totalLPRemaining -= calculatedFee;
                    sendLPTokensTo(feeAddresses[i], calculatedFee);
                }
            }

            // Keep it healthy
            pair.sync();

            // This prevents inside calls from triggering this function again (infinite loop)
            isSwapping = false;
        }

        // Always update liquidity total supply
        pairLiquidityTotalSupply = pair.totalSupply();

        return true;
    }

    function isLiquidityAdded() external view returns (bool) {
        return pairLiquidityTotalSupply < pair.totalSupply();
    }

    function isLiquidityRemoved() external view returns (bool) {
        return pairLiquidityTotalSupply > pair.totalSupply();
    }

    // Magical function that adds liquidity effortlessly
    function swapAndLiquify(uint256 tokens) private returns (uint256) {
        uint256 half = tokens / 2;
        uint256 initialRightBalance = rightSide.balanceOf(address(this));

        swapLeftSideForRightSide(half);

        uint256 newRightBalance = rightSide.balanceOf(address(this)) -
            initialRightBalance;

        addLiquidityToken(half, newRightBalance);

        emit SwapAndLiquify(half, initialRightBalance, newRightBalance);

        // Return the number of LP tokens this contract have
        return pair.balanceOf(address(this));
    }

    // Transfer LP tokens conveniently
    function sendLPTokensTo(address to, uint256 tokens) private {
        pair.transfer(to, tokens);
    }

    function createPairWith(address[2] memory path) private returns (IJoePair) {
        IJoeFactory factory = IJoeFactory(router.factory());
        address _pair;
        address _currentPair = factory.getPair(path[0], path[1]);
        if (_currentPair != address(0)) {
            _pair = _currentPair;
        } else {
            _pair = factory.createPair(path[0], path[1]);
        }
        return IJoePair(_pair);
    }

    function swapLeftSideForRightSide(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(leftSide);
        path[1] = address(rightSide);

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // Accept any amount
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidityToken(uint256 leftAmount, uint256 rightAmount)
        private
    {
        router.addLiquidity(
            address(leftSide),
            address(rightSide),
            leftAmount,
            rightAmount,
            0, // Slippage is unavoidable
            0, // Slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    // Views

    function getRouter() external view returns (address) {
        return address(router);
    }

    function getPair() external view returns (address) {
        return address(pair);
    }

    function getLeftSide() external view returns (address) {
        // Should be UNIV
        return address(leftSide);
    }

    function getRightSide() external view returns (address) {
        // Should be MIM
        return address(rightSide);
    }

    function isPair(address _pair) public view returns (bool) {
        return _pair == address(pair);
    }

    function isFeeReceiver(address _receiver) external view returns (bool) {
        for (uint256 i = 0; i < feeAddresses.length; i++) {
            if (feeAddresses[i] == _receiver) {
                return true;
            }
        }
        return false;
    }

    function isRouter(address _router) public view returns (bool) {
        return _router == address(router);
    }

    function getFeeAddresses() external view returns (address[] memory) {
        return feeAddresses;
    }

    function getFeePercentages() external view returns (uint8[] memory) {
        return feePercentages;
    }

    function getTreasuryAddress() external view returns (address) {
        return feeAddresses[0];
    }

    // Owner functions

    function setAllowance(bool active) public onlyOwner {
        // Gas optimization - Approval
        // There is no risk in giving unlimited allowance to the router
        // As long as it's a trusted one
        leftSide.safeApprove(address(router), (active ? MAX_UINT256 : 0));
        rightSide.safeApprove(address(router), (active ? MAX_UINT256 : 0));
    }

    function shouldLiquify(bool _liquifyEnabled) public onlyOwner {
        liquifyEnabled = _liquifyEnabled;
        setAllowance(_liquifyEnabled);
    }

    function updateSwapTokensToLiquidityThreshold(
        uint256 _swapTokensToLiquidityThreshold
    ) public onlyOwner {
        require(
            _swapTokensToLiquidityThreshold > 0,
            "LiquidityPoolManager: Number of coins to swap to liquidity must be defined"
        );
        swapTokensToLiquidityThreshold = _swapTokensToLiquidityThreshold;
    }

    function feesForwarder(
        address[] memory _feeAddresses,
        uint8[] memory _feePercentages
    ) public onlyOwner {
        require(
            _feeAddresses.length > 0,
            "LiquidityPoolManager: Addresses array length must be greater than zero"
        );
        require(
            _feeAddresses.length == _feePercentages.length + 1,
            "LiquidityPoolManager: Addresses arrays length mismatch. Remember last address receive the remains."
        );
        feeAddresses = _feeAddresses;
        feePercentages = _feePercentages;
    }

    function setFeeAddresses(address[] memory _feeAddresses) public onlyOwner {
        feeAddresses = _feeAddresses;
    }
}
