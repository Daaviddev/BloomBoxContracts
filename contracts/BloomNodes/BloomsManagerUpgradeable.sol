// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./interfaces/IMiniRouter.sol";
import "./interfaces/IWhitelist.sol";
import "./interfaces/IBloomNFT.sol";
import "./interfaces/IBloomsManagerUpgradeable.sol";

import "./implementations/NectarImplementationPointerUpgradeable.sol";

import "./libraries/BloomsManagerUpgradeableLib.sol";

import "hardhat/console.sol";

/**
 * ERROR DESCRIPTIONS:
 * 1: ERC721 balance is not 0, createBloomsWithTokens func
 * 2: _bloomValue is less than creation min price, or values are 0
 * 3: No value added, _whitelistedDeposit func, usdc.transferFrom failed, _nonWhitelistedDeposit func
 * 4: tierStorage.rewardMult is not equal to _multiplier, _logTier func
 * 5: newAmountLockedInTier is less than 0, _logTier func
 * 6: invalid _duration startAutocompounding func, startAutoCompounding func
 * 7: already locked for AutoCompounding, startAutoCompounding func
 * 8: not autocompounding, emergencyClaim func
 * 9: bloomId is 0, invalid bloomId _bloomExists func
 * 10: bloom does not exist, _getBloomIdsOf func
 * 11: not owner of blooms, onlyBloomOwner modifier
 * 12: not approved or owner, onlyApprovedOrOwnerOfBloom modifier
 * 13: invalid name, onlyValidName modifier
 * 14: not processable, autoCompound, autoClaim func
 */

contract BloomsManagerUpgradeable is
    Initializable,
    IBloomsManagerUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    NectarImplementationPointerUpgradeable
{
    using BloomsManagerUpgradeableLib for uint256;

    //
    // PUBLIC STATE VARIABLES
    //

    IWhitelist public whitelist;
    IMiniRouter public router;
    IERC20 public usdc;
    IBloomNFT public bloomNFT;

    uint8[10] public tierSlope;
    uint24[10] public tierLevel;

    uint256 public totalValueLocked;
    uint256 public creationMinPrice;
    uint256 public burnedFromRenaming;
    uint256 public rewardPerDay;
    uint256 public bloomCounter;
    uint256 public compoundDelay;
    address public treasury;

    mapping(uint256 => TierStorage) public tierTracking;

    //
    // PRIVATE STATE VARIABLES
    //

    uint256 private _lastUpdatedNodeIndex;
    uint256 private _lastUpdatedClaimIndex;

    uint256[] private _tiersTracked;
    uint256[] private _bloomsCompounding;
    uint256[] private _bloomsClaimable;

    mapping(address => EmergencyStats) private _emergencyStats;
    mapping(uint256 => BloomEntity) private _blooms;
    mapping(uint256 => uint256) private _bloomId2Index;

    uint256 private constant STANDARD_FEE = 10;
    uint256 private constant PRECISION = 100;

    //
    // MODIFIERS
    //

    modifier onlyBloomOwner() {
        require(_isOwnerOfBlooms(_msgSender()), "11");

        _;
    }

    modifier onlyApprovedOrOwnerOfBloom(uint256 _bloomId) {
        require(_isApprovedOrOwnerOfBloom(_msgSender(), _bloomId), "12");

        _;
    }

    modifier onlyValidName(string memory _bloomName) {
        require(
            bytes(_bloomName).length > 1 && bytes(_bloomName).length < 32,
            "13"
        );

        _;
    }

    //
    // EXTERNAL FUNCTIONS
    //

    /**
     * @dev - Initializes the contract and initiates necessary state variables
     * @param _router - Address of the router contract
     * @param _treasury - Address of the treasury
     * @param _usdc - Address of the $USDC.e token contract
     * @param _nctr - Address of the $NCTR token contract
     * @param _whitelist - Address of the whitelist contract
     * @param _rewardPerDay - Reward per day amount
     * @notice - Can only be initialized once
     */
    function initialize(
        address _router,
        address _treasury,
        address _usdc,
        address _nctr,
        address _bloomNFT,
        address _whitelist,
        uint256 _rewardPerDay
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        usdc = IERC20(_usdc);
        nectar = INectar(_nctr);
        bloomNFT = IBloomNFT(_bloomNFT);
        whitelist = IWhitelist(_whitelist);
        router = IMiniRouter(_router);
        treasury = _treasury;
        rewardPerDay = _rewardPerDay;

        // Initialize contract
        compoundDelay = 24 hours;
        creationMinPrice = 52000 ether; // TODO ask for min price

        tierLevel = [
            65000,
            80000,
            95000,
            110000,
            125000,
            140000,
            155000,
            170000,
            185000,
            200000
        ];
        tierSlope = [1, 5, 7, 11, 18, 29, 47, 77, 124, 200];
    }

    /**
     * @dev - Rename Bloom node
     * @param _bloomId - Id of the Bloom node
     * @param _bloomName - Name of the Bloom node
     */
    function renameBloom(uint256 _bloomId, string memory _bloomName)
        external
        nonReentrant
        whenNotPaused
        onlyApprovedOrOwnerOfBloom(_bloomId)
        onlyValidName(_bloomName)
    {
        BloomEntity storage bloom = _blooms[_bloomId];

        require(bloom.bloomValue > 0, "2");

        uint256 newBloomValue = (bloom.bloomValue * STANDARD_FEE) / PRECISION;
        uint256 feeAmount = bloom.bloomValue - newBloomValue;

        burnedFromRenaming += feeAmount;
        bloom.bloomValue = newBloomValue;

        _logTier(bloom.rewardMult, -int256(feeAmount));

        emit Rename(_msgSender(), bloom.name, _bloomName);

        bloom.name = _bloomName;
    }

    /**
     * @dev - Creates Bloom node
     * @param _bloomName - Name of the Bloom node
     * @param _bloomValue - Starting value of the Bloom node
     */
    function createBloomWithTokens(
        string memory _bloomName,
        uint256 _bloomValue
    ) external nonReentrant whenNotPaused onlyValidName(_bloomName) {
        require(_bloomValue >= creationMinPrice, "2");

        if (!whitelist.isWhitelisted(_msgSender())) {
            /// @notice user can possibly create more accounts and create one from each
            // If the user is not whitelisted, he can only create one node
            require(bloomNFT.balanceOf(_msgSender()) == 0, "1");
        }

        /// @notice - Actual _bloomValue, if the user deposited in $NCTR, returns _bloomValue
        ///           If not, quotes the value of $USDC.e deposit in $NCTR
        uint256 bloomValue = _deposit(_bloomValue);

        // Add this to the TVL
        totalValueLocked += bloomValue;

        _logTier(tierLevel[0], int256(bloomValue));

        // Add Bloom
        _blooms[++bloomCounter] = BloomEntity({
            owner: _msgSender(),
            id: bloomCounter,
            name: _bloomName,
            creationTime: block.timestamp,
            lastProcessingTimestamp: 0,
            rewardMult: tierLevel[0],
            bloomValue: bloomValue,
            totalClaimed: 0,
            timesCompounded: 0,
            lockedUntil: 0,
            lockPeriod: 0,
            exists: true
        });

        // Assign the Bloom to this account
        bloomNFT.mintBloom(_msgSender(), bloomCounter);

        emit Create(_msgSender(), bloomCounter, bloomValue);
    }

    /**
     * @dev - Adds more value to the existing Bloom node
     * @param _bloomId - Id of the Bloom node
     * @param _value - Value to add to the Bloom node
     */
    function addValue(uint256 _bloomId, uint256 _value)
        external
        nonReentrant
        whenNotPaused
        onlyApprovedOrOwnerOfBloom(_bloomId)
    {
        require(_value > 0, "2");

        BloomEntity storage bloom = _blooms[_bloomId];

        require(block.timestamp >= bloom.lockedUntil, "8");

        uint256 value = _deposit(_value);

        bloom.bloomValue += value;
        totalValueLocked += value;

        emit AdditionalDeposit(_bloomId, value);
    }

    /**
     * @dev - Registers the users Bloom node for auto compounding
     * @param _bloomId - Id of the Bloom node
     * @param _duration - Duration of the lock period for auto compounding, has to be in the specified timeframe
     */
    function startAutoCompounding(uint256 _bloomId, uint256 _duration)
        external
        onlyApprovedOrOwnerOfBloom(_bloomId)
    {
        BloomEntity storage bloom = _blooms[_bloomId];

        require(_isProcessable(bloom.lastProcessingTimestamp), "14");
        require(_duration >= 6 days && _duration <= 27 days, "6");
        require(block.timestamp >= bloom.lockedUntil, "7");

        bloom.lockedUntil = block.timestamp + _duration;
        bloom.lockPeriod = _duration;
        bloom.lastProcessingTimestamp = block.timestamp;

        if (_duration > 21 days) {
            // Increase reward multiplier by 0.25%
            bloom.rewardMult += 25000;
        } else if (_duration > 6 days) {
            // Increase reward multiplier by 0.15%
            bloom.rewardMult += 15000;
        }

        _bloomsCompounding.push(_bloomId);
        _bloomId2Index[_bloomId] = _bloomsCompounding.length - 1;
    }

    /**
     * @dev - Owner dependent auto compounding function, automatically compounds subscribed nodes
     * @param _numNodes- Number of the Bloom nodes to be compounded in one call
     * @notice - If the array is too large, the transaction wouldn't fit into the block,
     *         - therefore we introduced the _numNodes argument so the transaction wouldn't fail
     *         - It functions as a round robin system
     */
    // TODO test this
    function autoCompound(uint256 _numNodes) external onlyOwner {
        uint256 lastUpdatedNodeIndexLocal = _lastUpdatedNodeIndex;

        while (_numNodes > 0) {
            if (_bloomsCompounding.length == 0) {
                break;
            }
            if (_lastUpdatedNodeIndex >= _bloomsCompounding.length) {
                lastUpdatedNodeIndexLocal = 0;
            }

            // changed from _lastUpdatedNodeIndex to lastUpdatedNodeIndexLocal
            uint256 bloomId = _bloomsCompounding[lastUpdatedNodeIndexLocal];
            BloomEntity storage bloom = _blooms[bloomId];

            if (bloom.lockedUntil != 0 && block.timestamp > bloom.lockedUntil) {
                _resetRewardMultiplier(bloomId);
                _unsubscribeNodeFromAutoCompounding(lastUpdatedNodeIndexLocal);
                _bloomsClaimable.push(bloomId);
                continue;
            }

            (
                uint256 amountToCompound,
                uint256 feeAmount
            ) = _getRewardsAndCompound(bloomId);

            if (feeAmount > 0) {
                nectar.liquidityReward(feeAmount);
            }

            lastUpdatedNodeIndexLocal++;
            _numNodes--;

            emit Autocompound(msg.sender, bloomId, amountToCompound);
        }

        _lastUpdatedNodeIndex = lastUpdatedNodeIndexLocal;
        // console.log(_lastUpdatedNodeIndex);
    }

    /**
     * @dev - Claims the rewards of nodes that finished their autocompounding lock period
     * @notice - Can only be called by the owner
     * @param _numNodes - Number of nodes to run through
     */
    function autoClaim(uint256 _numNodes) external onlyOwner {
        // TODO loop through _claimable array, which is updated when a node is unsubscribed from autocompounding
        // TODO calculate the rewards for each bloom with a STANDARD_FEE, and it should not affect tierLevel
        uint256 lastUpdatedClaimIndexLocal = _lastUpdatedClaimIndex;

        while (_numNodes > 0) {
            if (_bloomsClaimable.length == 0) {
                break;
            }
            // changed from _lastUpdatedClaimIndex to lastUpdatedClaimIndexLocal
            if (lastUpdatedClaimIndexLocal >= _bloomsClaimable.length) {
                lastUpdatedClaimIndexLocal = 0;
            }

            // changed from _lastUpdatedClaimIndex to lastUpdatedClaimIndexLocal
            uint256 bloomId = _bloomsClaimable[lastUpdatedClaimIndexLocal];
            BloomEntity storage bloom = _blooms[bloomId];

            _removeNodeFromClaimable(lastUpdatedClaimIndexLocal);

            uint256 rewardAmount = _autoclaimRewards(bloomId);

            _cashoutReward(rewardAmount, STANDARD_FEE, bloom.owner);

            lastUpdatedClaimIndexLocal++;
            _numNodes--;

            emit Autoclaim(bloom.owner, bloomId, rewardAmount);
        }

        _lastUpdatedClaimIndex = lastUpdatedClaimIndexLocal;
    }

    /**
     * @dev - Claims the rewards of the users locked-for-autocompounding Bloom node
     * @notice - Fees for the emergencyClaim function are substantially higher than the normal claim function
     * @param _bloomId - Id of the Bloom node
     */
    function emergencyClaim(uint256 _bloomId)
        external
        nonReentrant
        whenNotPaused
        onlyApprovedOrOwnerOfBloom(_bloomId)
    {
        BloomEntity storage bloom = _blooms[_bloomId];
        require(block.timestamp < bloom.lockedUntil, "8");

        // bug - _bloomId2Index[_bloomId] will try to access the array at an out-of-bounds index, due to place-swapping and poping methods
        // FIXED
        _unsubscribeNodeFromAutoCompounding(_bloomId2Index[_bloomId]);
        _resetRewardMultiplier(_bloomId);

        uint256 amountToReward = _emergencyReward(_bloomId);
        uint256 emergencyFee = _updateEmergencyStatus(_msgSender())
            ._getEmergencyFee();

        bloom.lockedUntil = block.timestamp;
        bloom.totalClaimed += amountToReward;
        _cashoutReward(amountToReward, emergencyFee, bloom.owner);

        emit EmergencyClaim(
            _msgSender(),
            _bloomId,
            amountToReward,
            emergencyFee
        );
    }

    /**
     * @dev - Burns the specified Bloom node
     * @param _bloomId - ID of the bloom node
     */
    function burn(uint256 _bloomId)
        external
        override
        nonReentrant
        whenNotPaused
        onlyApprovedOrOwnerOfBloom(_bloomId)
    {
        _burn(_bloomId);
    }

    //
    // OWNER SETTER FUNCTIONS
    //

    /**
     * @dev - Changes the minimum price for the creation of a Bloom node
     * @param _creationMinPrice - Wanted minimum price of a Bloom node
     */
    function setNodeMinPrice(uint256 _creationMinPrice) external onlyOwner {
        creationMinPrice = _creationMinPrice;
    }

    /**
     * @dev - Changes the compound delay time
     * @param _compoundDelay - Wanted compound delay
     */
    function setCompoundDelay(uint256 _compoundDelay) external onlyOwner {
        compoundDelay = _compoundDelay;
    }

    /**
     * @dev - Sets the reward per day to the specified _amount
     * @param _amount - Wanted reward per day cap
     */
    function setRewardPerDay(uint256 _amount) external onlyOwner {
        rewardPerDay = _amount;
    }

    /**
     * @dev - Changes the tier levels and tier slope
     * @param _tierLevel - Wanted tier level array
     * @param _tierSlope - Wanted tier slope array
     * @notice - _tierLevel array contains reward multipliers, white _tierSlope contains the amount of compounds needed to increase the _tierLevel
     */
    function changeTierSystem(
        uint24[10] memory _tierLevel,
        uint8[10] memory _tierSlope
    ) external onlyOwner {
        tierLevel = _tierLevel;
        tierSlope = _tierSlope;
    }

    //
    // EXTERNAL VIEW FUNCTIONS
    //

    /**
     * @dev - Gets the BloomInfo of the specified number of Bloom nodes
     * @param _bloomIds - IDs of the Bloom nodes
     * @return BloomInfoEntity[] - Returns an array of info for the specified number of Bloom nodes
     */
    function getBloomsByIds(uint256[] memory _bloomIds)
        external
        view
        override
        returns (BloomInfoEntity[] memory)
    {
        BloomInfoEntity[] memory bloomsInfo = new BloomInfoEntity[](
            _bloomIds.length
        );

        for (uint256 i = 0; i < _bloomIds.length; i++) {
            BloomEntity memory bloom = _blooms[_bloomIds[i]];

            bloomsInfo[i] = BloomInfoEntity(
                bloom,
                _bloomIds[i],
                _calculateReward(bloom),
                _rewardPerDayFor(bloom),
                compoundDelay
            );
        }

        return bloomsInfo;
    }

    /**
     * @dev - Calculates the total daily rewards of all the tiers combined
     * @return uint256 - Returns the calculated daily emission amount
     */
    function calculateTotalDailyEmission()
        external
        view
        override
        returns (uint256)
    {
        uint256 dailyEmission = 0;
        for (uint256 i = 0; i < _tiersTracked.length; i++) {
            TierStorage memory tierStorage = tierTracking[_tiersTracked[i]];
            dailyEmission += tierStorage
                .amountLockedInTier
                ._calculateRewardsFromValue(
                    tierStorage.rewardMult,
                    compoundDelay,
                    rewardPerDay
                );
        }

        return dailyEmission;
    }

    //
    // PRIVATE FUNCTIONS
    //

    /**
     * @dev - Calculates Bloom cashout rewards and updates the state of the Bloom node
     * @param _bloomId - Id of the Bloom node
     * @notice - This function resets the progress of the Bloom node
     */
    function _emergencyReward(uint256 _bloomId) private returns (uint256) {
        BloomEntity storage bloom = _blooms[_bloomId];

        uint256 reward = _calculateReward(bloom);

        if (bloom.rewardMult > tierLevel[0]) {
            _logTier(bloom.rewardMult, -int256(bloom.bloomValue));

            for (uint256 i = 1; i < tierLevel.length; i++) {
                // TODO Is break necessary for the loop to stop?
                if (bloom.rewardMult == tierLevel[i]) {
                    bloom.rewardMult = tierLevel[i - 1];
                    bloom.timesCompounded = tierSlope[i - 1];

                    break;
                }
            }
            _logTier(bloom.rewardMult, int256(bloom.bloomValue));
        }

        bloom.lastProcessingTimestamp = block.timestamp;

        return reward;
    }

    /**
     * @dev - Calculates the Bloom compound rewards of the specified Bloom node and updates its state
     * @param _bloomId - Id of the Bloom node
     */
    function _getRewardsAndCompound(uint256 _bloomId)
        private
        returns (uint256, uint256)
    {
        BloomEntity storage bloom = _blooms[_bloomId];

        if (!_isProcessable(bloom.lastProcessingTimestamp)) {
            return (0, 0);
        }

        uint256 reward = _calculateReward(bloom);

        if (reward > 0) {
            (uint256 amountToCompound, uint256 feeAmount) = reward
                ._getProcessingFee(STANDARD_FEE);

            totalValueLocked += amountToCompound;

            // First remove the bloomValue out of the current tier, in case the reward multiplier increases
            _logTier(bloom.rewardMult, -int256(bloom.bloomValue));

            bloom.lastProcessingTimestamp = block.timestamp;
            bloom.bloomValue += amountToCompound;

            // Increase tierLevel
            bloom.rewardMult = _checkMultiplier(
                bloom.rewardMult,
                ++bloom.timesCompounded
            );

            // Add the bloomValue to the current tier
            _logTier(bloom.rewardMult, int256(bloom.bloomValue));

            return (amountToCompound, feeAmount);
        }

        return (0, 0);
    }

    /**
     * @dev - Mints the reward amount to the user, minus the fee, and burns the fee
     * @param _amount - Previously calculated reward amount of the user-owned Bloom node
     * @param _fee - Fee amount (could either be emergencyFee or constant CREATION_FEE)
     */
    function _cashoutReward(
        uint256 _amount,
        uint256 _fee,
        address _to
    ) private {
        require(_amount > 0, "2");
        (uint256 amountToReward, uint256 feeAmount) = _amount._getProcessingFee(
            _fee
        );

        nectar.mintNectar(_to, amountToReward);
        /// @notice - The burnNectar function will not work if there is not enough $NCTR in this contract
        ///           Meaning that the nectar.balanceOf(address(this)) always needs to be greater than the feeAmount
        nectar.burnNectar(address(this), feeAmount);
    }

    /**
     * @dev Updates tier storage
     * @param _multiplier - Bloom/Tier reward multiplier
     * @param _amount - Addition to amountLockedInTier
     */
    function _logTier(uint256 _multiplier, int256 _amount) private {
        TierStorage storage tierStorage = tierTracking[_multiplier];

        if (tierStorage.exists) {
            // TODO Check if this require is redundant
            require(tierStorage.rewardMult == _multiplier, "4");

            uint256 newAmountLockedInTier = uint256(
                int256(tierStorage.amountLockedInTier) + _amount
            );

            require(newAmountLockedInTier >= 0, "5");
            tierStorage.amountLockedInTier = newAmountLockedInTier;

            return;
        }

        // tier isn't registered exist, register it
        require(_amount > 0, "2");
        tierTracking[_multiplier] = TierStorage({
            rewardMult: _multiplier,
            amountLockedInTier: uint256(_amount),
            exists: true
        });

        _tiersTracked.push(_multiplier);
    }

    //
    // PRIVATE VIEW FUNCTIONS
    //

    /**
     * @dev - Increases the rewardMult param of the Bloom node if the number of compounds reached a certain threshold
     * @param _prevMult - Previous/current rewardMult of the Bloom node
     * @param _timesCompounded - Number of Bloom node compounds
     * @return - Either the increased or the previous/current multiplier
     */
    function _checkMultiplier(uint256 _prevMult, uint256 _timesCompounded)
        private
        view
        returns (uint256)
    {
        if (
            _prevMult < tierLevel[tierLevel.length - 1] &&
            _timesCompounded <= tierSlope[tierSlope.length - 1]
        ) {
            for (uint256 i = 0; i < tierSlope.length; i++) {
                if (_timesCompounded == tierSlope[i]) {
                    return tierLevel[i];
                }
            }
        }

        return _prevMult;
    }

    /**
     * @dev - Checks if the compoundDelay time has passed for the Bloom node
     * @param _lastProcessingTimestamp - Last time the Bloom node was processed
     * @return bool - Returns true if the compoundDelay has passed, false if it hasn't
     */
    function _isProcessable(uint256 _lastProcessingTimestamp)
        private
        view
        returns (bool)
    {
        return block.timestamp >= _lastProcessingTimestamp + compoundDelay;
    }

    /**
     * @dev - Calculates the rewards of the specified Bloom node
     * @param _bloom - Bloom node
     * @return uint256 - Returns the calculated reward amount
     */
    function _calculateReward(BloomEntity memory _bloom)
        private
        view
        returns (uint256)
    {
        return
            _bloom.bloomValue._calculateRewardsFromValue(
                _bloom.rewardMult,
                block.timestamp - _bloom.lastProcessingTimestamp,
                rewardPerDay
            );
    }

    /**
     * @dev - Calculates the rewards per day for the specified Bloom node
     * @param _bloom - Bloom node
     * @return uint256 - Returns the calculated reward per day amount
     */
    function _rewardPerDayFor(BloomEntity memory _bloom)
        private
        view
        returns (uint256)
    {
        return
            _bloom.bloomValue._calculateRewardsFromValue(
                _bloom.rewardMult,
                compoundDelay,
                rewardPerDay
            );
    }

    /**
     * @dev - Checks if the Bloom node exists
     * @param _bloomId - ID of the Bloom node
     */
    function _bloomExists(uint256 _bloomId) private view returns (bool) {
        require(_bloomId > 0, "9");
        BloomEntity memory bloom = _blooms[_bloomId];

        return bloom.exists;
    }

    /**
     * @dev - Checks if the user is an owner of a Bloom node
     * @param _account - Address of the specified user
     * @return bool - Returns True if the user is an owner, false if he's not
     */
    function _isOwnerOfBlooms(address _account) private view returns (bool) {
        return bloomNFT.balanceOf(_account) > 0;
    }

    /**
     * @dev - Checks if the specified user is the owner of the Bloom node or is approved
     * @param _account - Address of the specified user
     * @param _bloomId - ID of the Bloom node
     * @return bool - Returns true if the user is the owner or is approved by the owner
     */
    function _isApprovedOrOwnerOfBloom(address _account, uint256 _bloomId)
        private
        view
        returns (bool)
    {
        return bloomNFT.isApprovedOrOwner(_account, _bloomId);
    }

    //
    // TOKEN DISTRIBUTION FUNCTIONS
    //

    /**
     * @dev - Swaps half the amount of deposited $USDC.e for $NCTR
     *      - Burns the percentage (80%) of the swapped-for $NCTR and trasnfers the same percentage of $USDC.e to the treasury address
     *      - Adds the leftover percentage of both tokens (20%) to the liquidity pool
     * @param _value - Deposited value amount
     * @notice - Called when users create Bloom nodes with $USDC.e
     */
    function _swapAndBurn(uint256 _value) private {
        (
            uint256 half,
            uint256 usdcToTreasuryAmount,
            uint256 usdcToLiquidityAmount
        ) = _value._getAmounts();

        uint256 nctrAmountOut = _routerSwap(
            address(usdc),
            address(nectar),
            half
        );

        uint256 nctrBurnAmount = (nctrAmountOut * 80) / 100;
        uint256 nctrToLiquidityAmount = nctrAmountOut - nctrBurnAmount;

        nectar.burnNectar(address(this), nctrBurnAmount);
        usdc.transfer(treasury, usdcToTreasuryAmount);

        _routerAddLiquidity(nctrToLiquidityAmount, usdcToLiquidityAmount);
    }

    /**
     * @dev - Swaps tokenA for tokenB using the router function
     * @param _tokenA - Address of tokenA
     * @param _tokenB - Address of tokenB
     * @param _half - Half the deposited amount of tokens
     * @return uint256 - Returns the amount of tokenB it got out of the swap
     */
    function _routerSwap(
        address _tokenA,
        address _tokenB,
        uint256 _half
    ) private returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _tokenA;
        path[1] = _tokenB;

        uint256 tokenBAmountOut = router.swapExactTokensForTokens(
            _half,
            0,
            path,
            address(this),
            type(uint256).max
        )[1];

        return tokenBAmountOut;
    }

    /**
     * @dev - Adds liquidity to the liquidity pool
     * @param _nctrToLiquidityAmount - Amount of $NCTR to add
     * @param _usdcToLiquidityAmount - Amount of $USDC.e to add
     */
    function _routerAddLiquidity(
        uint256 _nctrToLiquidityAmount,
        uint256 _usdcToLiquidityAmount
    ) private {
        nectar.approve(address(router), _nctrToLiquidityAmount);
        usdc.approve(address(router), _usdcToLiquidityAmount);
        router.addLiquidity(
            address(usdc),
            address(nectar),
            _usdcToLiquidityAmount,
            _nctrToLiquidityAmount,
            0,
            0,
            address(router),
            type(uint256).max
        );
    }

    //
    // HELPER FUNCTIONS
    //

    /**
     * @dev Deposits USDC or NCTR based on the whitelist status of sender
     * @param _value - Value to deposit
     * @return nctrValue - If the user deposits in $USDC.e, calculations need to be made to get actual $NCTR value of the deposit
     */
    function _deposit(uint256 _value) private returns (uint256 nctrValue) {
        if (whitelist.isWhitelisted(_msgSender())) {
            nctrValue = _whitelistedDeposit(_value);
        } else {
            nctrValue = _nonWhitelistedDeposit(_value);
        }
    }

    /**
     * @dev Whitelist only deposit
     * @notice Deposits NCTR if it is approved, else deposits USDC
     * @param _value - Value to deposit
     * @return nctrValue - $USDC.e value quoted in $NCTR
     */
    function _whitelistedDeposit(uint256 _value)
        private
        returns (uint256 nctrValue)
    {
        if (nectar.transferFrom(_msgSender(), address(this), _value)) {
            nectar.burnNectar(address(this), _value);

            nctrValue = _value;
        } else if (usdc.transferFrom(_msgSender(), address(this), _value)) {
            _swapAndBurn(_value);

            (uint256 reserveOut, uint256 reserveIn) = router.getReserves();
            nctrValue = router.getAmountOut(_value, reserveIn, reserveOut);
        } else {
            revert("3");
        }
    }

    /**
     * @dev Non whitelist deposit
     * @notice Deposits USDC
     * @param _value - Value to deposit
     * @return nctrValue - $USDC.e value quoted in $NCTR
     */
    function _nonWhitelistedDeposit(uint256 _value)
        private
        returns (uint256 nctrValue)
    {
        require(usdc.transferFrom(_msgSender(), address(this), _value), "3");
        _swapAndBurn(_value);

        (uint256 reserveOut, uint256 reserveIn) = router.getReserves();
        nctrValue = router.getAmountOut(_value, reserveIn, reserveOut);
    }

    /**
     * @dev - Unsubscribes the Bloom node from auto compounding when the specified lock period is over
     * @param _nodeIndex - Index of the Bloom node in the array
     */
    function _unsubscribeNodeFromAutoCompounding(uint256 _nodeIndex) private {
        if (_bloomsCompounding.length == 1) {
            _bloomsCompounding.pop();
            return;
        }

        // Get the bloomId of the node which will be swapped for and delete it from the current position
        uint256 bloomIdToKeep = _bloomsCompounding[
            _bloomsCompounding.length - 1
        ];
        uint256 indexTo = _nodeIndex;
        delete _bloomId2Index[bloomIdToKeep];

        // Swap to last position in the array so bloomId at _bloomsCompounding[_nodeIndex] can be popped
        _bloomsCompounding[_nodeIndex] = _bloomsCompounding[
            _bloomsCompounding.length - 1
        ];

        // Delete popped bloomId from mapping
        uint256 bloomIdToDelete = _bloomsCompounding[_nodeIndex];
        delete _bloomId2Index[bloomIdToDelete];

        // Add swapped-for bloomId back to the mapping at _nodeIndex
        _bloomId2Index[bloomIdToKeep] = indexTo;

        // Pop _bloomsCompounding[_nodeIndex] from the array
        _bloomsCompounding.pop();
    }

    /**
     * @dev - Removes the Bloom node from the _bloomsClaimable array once the rewards are claimed with the autoclaim function
     * @param _nodeIndex - Index of the Bloom node in the array
     */
    function _removeNodeFromClaimable(uint256 _nodeIndex) private {
        if (_bloomsClaimable.length == 1) {
            _bloomsClaimable.pop();
            return;
        }

        _bloomsClaimable[_nodeIndex] = _bloomsClaimable[
            _bloomsClaimable.length - 1
        ];
        _bloomsClaimable.pop();
    }

    /**
     * @dev - Checks and updates the emergency stats of the sender
     * @param _sender - Address of the emergencyClaim caller
     * @return uint256 - Returns the number of user emergency claims in a week
     */
    function _updateEmergencyStatus(address _sender) private returns (uint256) {
        EmergencyStats storage emergencyStats = _emergencyStats[_sender];

        if (block.timestamp >= 7 days + emergencyStats.emergencyClaimTime) {
            emergencyStats.userEmergencyClaims = 0;
            emergencyStats.emergencyClaimTime = block.timestamp;
        }

        return ++emergencyStats.userEmergencyClaims;
    }

    /**
     * @dev - Calculates the rewards for the autoclaim function and updates Bloom stats
     * @param _bloomId - Id of the Bloom node
     */
    function _autoclaimRewards(uint256 _bloomId) private returns (uint256) {
        BloomEntity storage bloom = _blooms[_bloomId];
        require(_isProcessable(bloom.lastProcessingTimestamp), "14");

        uint256 reward = _calculateReward(bloom);

        bloom.totalClaimed += reward;
        bloom.lastProcessingTimestamp = block.timestamp;

        return reward;
    }

    /**
     * @dev - Resets the reward multiplier if it was increased when the Bloom node was locked for autocompounding
     * @param _bloomId - Id of the Bloom node
     */
    function _resetRewardMultiplier(uint256 _bloomId) private {
        BloomEntity storage bloom = _blooms[_bloomId];

        uint256 multiplier;

        if (bloom.lockPeriod > 6 days) {
            multiplier = 15000;
        } else if (bloom.lockPeriod > 21 days) {
            multiplier = 25000;
        } else {
            multiplier = 0;
        }
        bloom.rewardMult -= multiplier;
    }

    //
    // OVERRIDES
    //

    /**
     * @dev - Burns the Bloom node of the _tokenId, and removes its value from the tier
     * @param _tokenId - ID of the Bloom node
     */
    // TODO Could possibly rename this function
    function _burn(uint256 _tokenId) internal {
        BloomEntity storage bloom = _blooms[_tokenId];
        bloom.exists = false;

        _logTier(bloom.rewardMult, -int256(bloom.bloomValue));

        bloomNFT.burnBloom(_tokenId);
    }
}

//
// REDUNDANT FUNCTIONS
//

// /**
//  * @dev - Claims the earned reward of the Bloom node
//  * @param _bloomId - Id of the Bloom node
//  */
// function cashoutReward(uint256 _bloomId)
//     external
//     nonReentrant
//     whenNotPaused
//     onlyApprovedOrOwnerOfBloom(_bloomId)
// {
//     BloomEntity memory bloom = _blooms[_bloomId];
//     require(block.timestamp >= bloom.lockedUntil, "8");

//     uint256 amountToReward = _emergencyReward(_bloomId);
//     _cashoutReward(amountToReward, STANDARD_FEE);

//     emit Cashout(_msgSender(), _bloomId, amountToReward);
// }

// /**
//  * @dev - Claims the earned rewards of all the user-owned Bloom nodes
//  */
// function cashoutAll() external nonReentrant whenNotPaused onlyBloomOwner {
//     uint256 rewardsTotal = 0;
//     uint256[] memory bloomsOwned = _getBloomIdsOf(_msgSender());

//     for (uint256 i = 0; i < bloomsOwned.length; i++) {
//         if (block.timestamp < _blooms[bloomsOwned[i]].lockedUntil) {
//             continue;
//         }

//         rewardsTotal += _emergencyReward(bloomsOwned[i]);
//     }

//     if (rewardsTotal == 0) {
//         return;
//     }

//     _cashoutReward(rewardsTotal, STANDARD_FEE);

//     emit CashoutAll(_msgSender(), bloomsOwned, rewardsTotal);
// }

// /**
//  * @dev - Compounds the earned reward of the Bloom node
//  * @param _bloomId - Id of the Bloom node
//  */
// function compoundReward(uint256 _bloomId)
//     external
//     nonReentrant
//     whenNotPaused
//     onlyApprovedOrOwnerOfBloom(_bloomId)
// {
//     (uint256 amountToCompound, uint256 feeAmount) = _getRewardsAndCompound(
//         _bloomId
//     );

//     if (feeAmount > 0) {
//         nectar.liquidityReward(feeAmount);
//     }

//     if (amountToCompound <= 0) {
//         return;
//     }

//     emit Compound(_msgSender(), _bloomId, amountToCompound);
// }

// /**
//  * @dev - Compounds the earned rewards of all the user-owned Bloom nodes
//  */
// function compoundAll() external nonReentrant whenNotPaused onlyBloomOwner {
//     uint256 feesAmount = 0;
//     uint256 amountToCompoundSum = 0;

//     uint256[] memory bloomsOwned = _getBloomIdsOf(_msgSender());
//     uint256[] memory bloomsAffected = new uint256[](bloomsOwned.length);

//     for (uint256 i = 0; i < bloomsOwned.length; i++) {
//         (
//             uint256 amountToCompound,
//             uint256 feeAmount
//         ) = _getRewardsAndCompound(bloomsOwned[i]);

//         if (amountToCompound > 0) {
//             bloomsAffected[i] = bloomsOwned[i];
//             feesAmount += feeAmount;
//             amountToCompoundSum += amountToCompound;
//         } else {
//             delete bloomsAffected[i];
//         }
//     }

//     if (feesAmount > 0) {
//         nectar.liquidityReward(feesAmount);
//     }

//     emit CompoundAll(_msgSender(), bloomsAffected, amountToCompoundSum);
// }

// /**
//  * @dev - Swaps half the amount of deposited $NCTR for $USDC.e
//  *      - Burns the percentage (80%) of the leftover $NCTR and trasnfers the same percentage of $USDC.e to the treasury address
//  *      - Adds the leftover percentage of both (20%) to the liquidity pool
//  * @param _value - Deposited value amount
//  * @notice - Called when whitelisted users create Bloom nodes with $NCTR
//  */
// function _burnAndSend(uint256 _value) private {
//     (
//         uint256 half,
//         uint256 nctrBurnAmount,
//         uint256 nctrToLiquidityAmount
//     ) = _value._getAmounts();

//     uint256 usdcAmountOut = _routerSwap(
//         address(nectar),
//         address(usdc),
//         half
//     );

//     uint256 usdcToTreasuryAmount = (usdcAmountOut * 80) / 100;
//     uint256 usdcToLiquidityAmount = usdcAmountOut - usdcToTreasuryAmount;

//     nectar.burnNectar(address(this), nctrBurnAmount);
//     usdc.transfer(treasury, usdcToTreasuryAmount);

//     _routerAddLiquidity(nctrToLiquidityAmount, usdcToLiquidityAmount);
// }

// /**
//  * @dev - Gets the IDs of all the user-owned Bloom nodes
//  * @param _account - User's address
//  * @return uint256[] - Returns an array of Bloom node IDs
//  */
// function _getBloomIdsOf(address _account)
//     private
//     view
//     returns (uint256[] memory)
// {
//     uint256 numberOfblooms = balanceOf(_account);
//     uint256[] memory bloomIds = new uint256[](numberOfblooms);

//     for (uint256 i = 0; i < numberOfblooms; i++) {
//         uint256 bloomId = tokenOfOwnerByIndex(_account, i);
//         require(_bloomExists(bloomId), "10");

//         bloomIds[i] = bloomId;
//     }

//     return bloomIds;
// }
