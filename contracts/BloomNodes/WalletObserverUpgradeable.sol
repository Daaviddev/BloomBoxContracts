// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IJoePair.sol";
import "./OwnerRecoveryUpgradeable.sol";
import "./implementations/NectarImplementationPointerUpgradeable.sol";
import "./implementations/LiquidityPoolManagerImplementationPointerUpgradeable.sol";
import "./implementations/BloomsManagerImplementationPointerUpgradeable.sol";

// TODO - Check the functionality of this contract and if its necessary
contract WalletObserverUpgradeable is
    Initializable,
    OwnableUpgradeable,
    OwnerRecoveryUpgradeable,
    NectarImplementationPointerUpgradeable,
    LiquidityPoolManagerImplementationPointerUpgradeable,
    BloomsManagerImplementationPointerUpgradeable
{
    mapping(address => uint256) public _boughtTokens;
    mapping(uint256 => mapping(address => int256)) public _inTokens;
    mapping(uint256 => mapping(address => uint256)) public _outTokens;
    mapping(address => bool) public _isDenied;
    mapping(address => bool) public _isExcludedFromObserver;

    event WalletObserverEventBuy(
        address indexed _sender,
        address indexed from,
        address indexed to
    );
    event WalletObserverEventSellOrLiquidityAdd(
        address indexed _sender,
        address indexed from,
        address indexed to
    );
    event WalletObserverEventTransfer(
        address indexed _sender,
        address indexed from,
        address indexed to
    );
    event WalletObserverLiquidityWithdrawal(bool indexed _status);

    // Current time window
    uint256 private timeframeCurrent;

    uint256 private maxTokenPerWallet;

    // The TIMEFRAME in seconds
    uint256 private timeframeExpiresAfter;

    // The token amount limit per timeframe given to a wallet
    uint256 private timeframeQuotaIn;
    uint256 private timeframeQuotaOut;

    bool private _decode_771274418637067024507;

    // Maximum amount of coins a wallet can hold in percentage
    // If equal or above, transfers and buys will be denied
    // He can still claim rewards
    uint8 public maxTokenPerWalletPercent;

    mapping(address => uint256) public _lastBuyOf;
    mapping(address => uint256) public _lastSellOf;

    function initialize() external initializer {
        __Ownable_init();

        _decode_771274418637067024507 = false;

        // By default set every day
        setTimeframeExpiresAfter(4 hours);

        // Timeframe buys / transfers to 0.25% of the supply per wallet
        // 0.25% of 42 000 000 000 = 105 000 000
        setTimeframeQuotaIn(100_000_000 * (10**18));
        setTimeframeQuotaOut((100_000_000 / 10) * (10**18));

        // Limit token to 1% of the supply per wallet (we don't count rewards)
        // 1% of 42 000 000 000 = 420 000 000
        //setMaxTokenPerWalletPercent(1);

        excludeFromObserver(owner(), true);
    }

    modifier checkTimeframe() {
        uint256 _currentTime = block.timestamp;
        if (_currentTime > timeframeCurrent + timeframeExpiresAfter) {
            timeframeCurrent = _currentTime;
        }
        _;
    }

    modifier isNotDenied(
        address _sender,
        address from,
        address to,
        address txOrigin
    ) {
        // Allow owner to receive tokens from denied addresses
        // Useful in case of refunds
        if (txOrigin != owner() && to != owner()) {
            require(
                !_isDenied[_sender] &&
                    !_isDenied[from] &&
                    !_isDenied[to] &&
                    !_isDenied[txOrigin],
                "WalletObserverUpgradeable: Denied address"
            );
        }
        _;
    }

    function changeNectarImplementation(address newImplementation)
        public
        virtual
        override(NectarImplementationPointerUpgradeable)
        onlyOwner
    {
        super.changeNectarImplementation(newImplementation);
        excludeFromObserver(nectar.owner(), true);
    }

    function changeLiquidityPoolManagerImplementation(address newImplementation)
        public
        virtual
        override(LiquidityPoolManagerImplementationPointerUpgradeable)
        onlyOwner
    {
        super.changeLiquidityPoolManagerImplementation(newImplementation);
        excludeFromObserver(newImplementation, true);
    }

    // Temporary
    function isPair(address _sender, address from)
        internal
        view
        returns (bool)
    {
        // DAI.e
        if (
            _sender == address(0x7184EaAAcA3aB3A31AF0541eE2C6F2eAe3cA9181) &&
            from == address(0x7184EaAAcA3aB3A31AF0541eE2C6F2eAe3cA9181)
        ) {
            return true;
        }

        // USDC.e
        if (
            _sender == address(0x3604A23AA6dF617fde74af160f653B4Cd937BBa9) &&
            from == address(0x3604A23AA6dF617fde74af160f653B4Cd937BBa9)
        ) {
            return true;
        }

        // MIM
        return
            liquidityPoolManager.isPair(_sender) &&
            liquidityPoolManager.isPair(from);
    }

    function beforeTokenTransfer(
        address _sender,
        address from,
        address to,
        uint256 amount
    )
        external
        onlyNectar
        checkTimeframe
        isNotDenied(_sender, from, to, tx.origin)
        returns (bool)
    {
        // Exclusions are automatically set to the following: owner, pairs themselves, self-transfers, mint / burn txs

        // Do not observe self-transfers
        if (from == to) {
            return true;
        }

        // Do not observe mint / burn
        if (from == address(0) || to == address(0)) {
            return true;
        }

        // Do not observe OTC desk
        if (
            from == address(0x955C1103c5b584feA4F79672Cb3880Ec09A33Aa0) ||
            to == address(0x955C1103c5b584feA4F79672Cb3880Ec09A33Aa0)
        ) {
            return true;
        }

        // Prevent common mistakes
        require(
            to != address(bloomsManager),
            "WalletObserverUpgradeable: Cannot send directly tokens to planetsManager, use the Observatory to create a planet (https://univ.money/observatory)"
        );
        require(
            to != address(liquidityPoolManager),
            "WalletObserverUpgradeable: Cannot send directly tokens to liquidityPoolManager, tokens are automatically collected"
        );
        require(
            to != address(nectar),
            "WalletObserverUpgradeable: The main contract doesn't accept tokens"
        );
        require(
            to != address(this),
            "WalletObserverUpgradeable: WalletObserver doesn't accept tokens"
        );

        // Prevent inter-LP transfers
        /*if (isPair(from, from) && isPair(to, to)) {
            revert(
                "WalletObserverUpgradeable: Cannot directly transfer from one LP to another"
            );
        }*/

        bool isBuy = false;
        bool isSellOrLiquidityAdd = false;

        if (isPair(_sender, from)) {
            isBuy = true;
            if (!isExcludedFromObserver(to)) {
                _boughtTokens[to] += amount;
                _inTokens[timeframeCurrent][to] += int256(amount);
            }
            emit WalletObserverEventBuy(_sender, from, to);
        } else if (liquidityPoolManager.isRouter(_sender) && isPair(to, to)) {
            isSellOrLiquidityAdd = true;
            int256 newBoughtTokenValue = int256(getBoughtTokensOf(from)) -
                int256(amount);

            // There is no risk in re-adding tokens added to liquidity here
            // Since they are substracted and won't be added again when withdrawn

            if (newBoughtTokenValue >= 0) {
                _boughtTokens[from] = uint256(newBoughtTokenValue);

                _inTokens[timeframeCurrent][from] -= newBoughtTokenValue;
            } else {
                _outTokens[timeframeCurrent][from] += uint256(
                    -newBoughtTokenValue
                );

                _inTokens[timeframeCurrent][from] -= int256(
                    getBoughtTokensOf(from)
                );

                _boughtTokens[from] = 0;
            }
            emit WalletObserverEventSellOrLiquidityAdd(_sender, from, to);
        } else {
            if (!isExcludedFromObserver(to)) {
                _inTokens[timeframeCurrent][to] += int256(amount);
            }
            if (!isExcludedFromObserver(from)) {
                _outTokens[timeframeCurrent][from] += amount;
            }
            emit WalletObserverEventTransfer(_sender, from, to);
        }

        // Have a minimum per buy / sell
        //if (isBuy || isSellOrLiquidityAdd) {
        require(
            amount >= 100_000 * (10**18),
            "WalletObserverUpgradeable: Buy or sell must be at least 100K UNIV"
        );
        //}

        if (!isExcludedFromObserver(to)) {
            // Revert if the receiving wallet exceed the maximum a wallet can hold
            require(
                getMaxTokenPerWallet() >= nectar.balanceOf(to) + amount,
                "WalletObserverUpgradeable: Cannot transfer to this wallet, it would exceed the limit per wallet. [balanceOf > maxTokenPerWallet]"
            );

            // Revert if receiving wallet exceed daily limit
            require(
                getRemainingTransfersIn(to) >= 0,
                "WalletObserverUpgradeable: Cannot transfer to this wallet for this timeframe, it would exceed the limit per timeframe. [_inTokens > timeframeLimit]"
            );
        }

        if (!isExcludedFromObserver(from)) {
            // Ensure last buy isn't 60 blocks ago
            require(
                block.number > _lastSellOf[from] + 10 || _lastSellOf[from] == 0,
                "WalletObserverUpgradeable: You must either be an arbitrage or front-running bot!"
            );
            if (isSellOrLiquidityAdd) {
                _lastSellOf[from] = block.number;
            }

            // Have a limit of timeframeQuotaOut
            /*if (!isBuy) {
                require(
                    timeframeQuotaOut >= amount,
                    "WalletObserverUpgradeable: You are limited to 7M UNIV per sell/transfer"
                );
            }*/

            // Revert if the sending wallet exceed the maximum transfer limit per day
            // We take into calculation the number ever bought of tokens available at this point
            if (isSellOrLiquidityAdd) {
                require(
                    getRemainingTransfersOutWithSellAllowance(from) >= 0,
                    "WalletObserverUpgradeable: Cannot sell from this wallet for this timeframe, it would exceed the limit per timeframe. [_outTokens > timeframeLimit]"
                );
            } else {
                require(
                    getRemainingTransfersOut(from) >= 0,
                    "WalletObserverUpgradeable: Cannot transfer out from this wallet for this timeframe, it would exceed the limit per timeframe. [_outTokens > timeframeLimit]"
                );
            }
        }

        return true;
    }

    function getMaxTokenPerWallet() public view returns (uint256) {
        // 1% - variable
        return (nectar.totalSupply() * maxTokenPerWalletPercent) / 100;
    }

    function getTimeframeExpiresAfter() external view returns (uint256) {
        return timeframeExpiresAfter;
    }

    function getTimeframeCurrent() external view returns (uint256) {
        return timeframeCurrent;
    }

    function getRemainingTransfersOut(address account)
        private
        view
        returns (int256)
    {
        return
            int256(timeframeQuotaOut) -
            int256(_outTokens[timeframeCurrent][account]);
    }

    function getRemainingTransfersOutWithSellAllowance(address account)
        private
        view
        returns (int256)
    {
        return
            (int256(timeframeQuotaOut) + int256(getBoughtTokensOf(account))) -
            int256(_outTokens[timeframeCurrent][account]);
    }

    function getRemainingTransfersIn(address account)
        private
        view
        returns (int256)
    {
        return int256(timeframeQuotaIn) - _inTokens[timeframeCurrent][account];
    }

    function getOverviewOf(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            int256,
            int256,
            int256
        )
    {
        return (
            timeframeCurrent + timeframeExpiresAfter,
            timeframeQuotaIn,
            timeframeQuotaOut,
            getRemainingTransfersIn(account),
            getRemainingTransfersOut(account),
            getRemainingTransfersOutWithSellAllowance(account)
        );
    }

    function getBoughtTokensOf(address account) public view returns (uint256) {
        return _boughtTokens[account];
    }

    function isWalletFull(address account) public view returns (bool) {
        return nectar.balanceOf(account) >= getMaxTokenPerWallet();
    }

    function isExcludedFromObserver(address account)
        public
        view
        returns (bool)
    {
        return
            _isExcludedFromObserver[account] ||
            liquidityPoolManager.isRouter(account) ||
            liquidityPoolManager.isPair(account) ||
            liquidityPoolManager.isFeeReceiver(account);
    }

    function setMaxTokenPerWalletPercent(uint8 _maxTokenPerWalletPercent)
        public
        onlyOwner
    {
        require(
            _maxTokenPerWalletPercent > 0,
            "WalletObserverUpgradeable: Max token per wallet percentage cannot be 0"
        );

        // Modifying this with a lower value won't brick wallets
        // It will just prevent transferring / buys to be made for them
        maxTokenPerWalletPercent = _maxTokenPerWalletPercent;
        require(
            getMaxTokenPerWallet() >= timeframeQuotaIn,
            "WalletObserverUpgradeable: Max token per wallet must be above or equal to timeframeQuotaIn"
        );
    }

    function resetBoughtTokensOf(address account) external onlyOwner {
        _boughtTokens[account] = 0;
    }

    function setTimeframeExpiresAfter(uint256 _timeframeExpiresAfter)
        public
        onlyOwner
    {
        require(
            _timeframeExpiresAfter > 0,
            "WalletObserverUpgradeable: Timeframe expiration cannot be 0"
        );
        timeframeExpiresAfter = _timeframeExpiresAfter;
    }

    function setTimeframeQuotaIn(uint256 _timeframeQuotaIn) public onlyOwner {
        require(
            _timeframeQuotaIn > 0,
            "WalletObserverUpgradeable: Timeframe token quota in cannot be 0"
        );
        timeframeQuotaIn = _timeframeQuotaIn;
    }

    function setTimeframeQuotaOut(uint256 _timeframeQuotaOut) public onlyOwner {
        require(
            _timeframeQuotaOut > 0,
            "WalletObserverUpgradeable: Timeframe token quota out cannot be 0"
        );
        timeframeQuotaOut = _timeframeQuotaOut;
    }

    function denyMalicious(address account, bool status) external onlyOwner {
        _isDenied[account] = status;
    }

    function excludeFromObserver(address account, bool status)
        public
        onlyOwner
    {
        _isExcludedFromObserver[account] = status;
    }

    function totalSupply() external view returns (uint256) {
        uint256 _totalSupply = nectar.totalSupply();

        // Ignore Treasury wallets
        _totalSupply -= nectar.balanceOf(
            0x747218E40fF47bE6869d7Ea3BDc74ae879dac7c4 // Marketing
        );
        _totalSupply -= nectar.balanceOf(
            0x1acC825C922BBC9c6e4c03ECD929Bc8f73F9e363 // Donations
        );
        _totalSupply -= nectar.balanceOf(
            0x070b2b1F138FdEC6D6Cb3c47d8A74D5715c26Abf // Dev
        );
        _totalSupply -= nectar.balanceOf(
            0x20e5D2308F560060C7eC1a8454774209D9Bf1F31 // Treasury Invest
        );

        return _totalSupply;
    }
}