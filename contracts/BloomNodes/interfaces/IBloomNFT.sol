// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IBloomNFT {
    /**
     * @dev - Mint function
     * @param _to - Address of the user
     * @param _tokenId - ID of the token the user wants
     */
    function mintBloom(address _to, uint256 _tokenId) external;

    /**
     * @dev - Burn function
     * @param _tokenId - ID of the token the user wants
     */
    function burnBloom(uint256 _tokenId) external;

    function isApprovedOrOwner(address _spender, uint256 _tokenId)
        external
        view
        returns (bool);

    function balanceOf(address owner) external view returns (uint256 balance);
}
