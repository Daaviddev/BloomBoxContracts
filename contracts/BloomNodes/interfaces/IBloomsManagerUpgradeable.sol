// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IBloomsManagerUpgradeable {
    error Value();

    event Autoclaim(
        address indexed account,
        uint256 indexed bloomId,
        uint256 rewardAmount
    );

    event Autocompound(
        address indexed account,
        uint256 indexed bloomId,
        uint256 amountToCompound
    );

    event EmergencyClaim(
        address indexed account,
        uint256 indexed bloomId,
        uint256 amountToReward,
        uint256 emergencyFee
    );

    event Create(
        address indexed account,
        uint256 indexed newbloomId,
        uint256 amount
    );

    event Rename(
        address indexed account,
        string indexed previousName,
        string indexed newName
    );

    event AdditionalDeposit(uint256 indexed bloomId, uint256 amount);

    struct BloomInfoEntity {
        BloomEntity Bloom;
        uint256 id;
        uint256 pendingRewards;
        uint256 rewardPerDay;
        uint256 compoundDelay;
    }

    struct BloomEntity {
        address owner;
        uint256 id;
        string name;
        uint256 creationTime;
        uint256 lastProcessingTimestamp;
        uint256 rewardMult;
        uint256 bloomValue;
        uint256 totalClaimed;
        uint256 timesCompounded;
        uint256 lockedUntil;
        uint256 lockPeriod;
        bool exists;
    }

    struct TierStorage {
        uint256 rewardMult;
        uint256 amountLockedInTier;
        bool exists;
    }

    struct EmergencyStats {
        uint256 userEmergencyClaims;
        uint256 emergencyClaimTime;
    }

    function renameBloom(uint256 _bloomId, string memory _bloomName) external;

    function createBloomWithTokens(
        string memory _bloomName,
        uint256 _bloomValue
    ) external;

    function addValue(uint256 _bloomId, uint256 _value) external;

    function startAutoCompounding(uint256 _bloomId, uint256 _duration) external;

    function emergencyClaim(uint256 _bloomId) external;

    function calculateTotalDailyEmission() external view returns (uint256);

    function getBloomsByIds(uint256[] memory _bloomIds)
        external
        view
        returns (BloomInfoEntity[] memory);

    function burn(uint256 _bloomId) external;
}

//
// REDUNDANT FUNCTIONS
//

// function cashoutReward(uint256 _bloomId) external;

// function cashoutAll() external;

// function compoundReward(uint256 _bloomId) external;

// function compoundAll() external;
