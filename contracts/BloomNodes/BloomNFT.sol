// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract BloomNFT is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    //
    // PUBLIC STATE VARIABLES
    //

    string public baseURI;

    //
    // PRIVATE STATE VARIABLES
    //

    address private _bloomNodes;

    //
    // MODIFIERS
    //

    modifier onlyBloomManagerOrOwner() {
        require(
            _msgSender() == _bloomNodes || _msgSender() == owner(),
            "Not approved"
        );

        _;
    }

    //
    // EXTERNAL FUNCTIONS
    //

    /**
     * @dev - Initializes this and other necessary contracts
     * @param bloomNodes_ - Address of the BloomsManagerUpgradeable contract
     * @notice - Can only be initialized once
     */
    function initialize(address bloomNodes_, string memory baseURI_)
        external
        initializer
    {
        __Ownable_init();
        __ERC721_init("BloomNFT", "Bloom");

        _bloomNodes = bloomNodes_;
        baseURI = baseURI_;
    }

    /**
     * @dev - Mint function
     * @param _to - Address of the user
     * @param _tokenId - ID of the token the user wants
     */
    function mintBloom(address _to, uint256 _tokenId)
        external
        nonReentrant
        onlyBloomManagerOrOwner
    {
        _mint(_to, _tokenId);
    }

    /**
     * @dev - Burn function
     * @param _tokenId - ID of the token the user wants
     */
    function burnBloom(uint256 _tokenId)
        external
        nonReentrant
        onlyBloomManagerOrOwner
    {
        _burn(_tokenId);
    }

    function isApprovedOrOwner(address _spender, uint256 _tokenId)
        external
        view
        returns (bool)
    {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    //
    // OWNER FUNCTIONS
    //

    function setBloomNodes(address _newBloomNodes) external onlyOwner {
        _bloomNodes = _newBloomNodes;
    }

    /**
     * @dev - Sets the base URI for Bloom nodes
     * @param baseURI_ - Base URI link
     */
    function setBaseURI(string memory baseURI_) external onlyOwner {
        baseURI = baseURI_;
    }

    //
    // OVERRIDES
    //

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
