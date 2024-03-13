// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

library BloomsManagerUpgradeableLib {
    // Calculates the fee amount when the user uses the emergencyClaim function
    // based on the amount of emergency claims made in a week
    function _getEmergencyFee(uint256 _emergencyClaims)
        internal
        pure
        returns (uint256 emergencyFeeAmount)
    {
        if (_emergencyClaims == 1) {
            emergencyFeeAmount = 50;
        } else if (_emergencyClaims == 2) {
            emergencyFeeAmount = 60;
        } else if (_emergencyClaims == 3) {
            emergencyFeeAmount = 70;
        } else if (_emergencyClaims == 4) {
            emergencyFeeAmount = 80;
        } else {
            emergencyFeeAmount = 90;
        }
    }

    // Private view functions
    function _getProcessingFee(uint256 _rewardAmount, uint256 _feeAmount)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 feeAmount = 0;
        if (_feeAmount > 0) {
            feeAmount = (_rewardAmount * _feeAmount) / 100;
        }

        return (_rewardAmount - feeAmount, feeAmount);
    }

    function _calculateRewardsFromValue(
        uint256 _bloomValue,
        uint256 _rewardMult,
        uint256 _timeRewards,
        uint256 _rewardPerDay
    ) internal pure returns (uint256) {
        uint256 rewards = (_timeRewards * _rewardPerDay) / 1000000;
        uint256 rewardsMultiplied = (rewards * _rewardMult) / 100000;
        return (rewardsMultiplied * _bloomValue) / 100000;
    }

    function _getAmounts(uint256 _value)
        internal
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 half = _value / 2;
        uint256 burnOrTreasuryPercentage = (half * 80) / 100;
        uint256 liquidityPercentage = half - burnOrTreasuryPercentage;

        return (half, burnOrTreasuryPercentage, liquidityPercentage);
    }
}
