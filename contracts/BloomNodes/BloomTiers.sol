// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract BloomTiers is
    Initializable,
    ERC1155URIStorageUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    //
    // PUBLIC STATE VARIABLES
    //

    /**
     * @dev - Each one of these state variables represents an unique token ID
     * @notice - These tokens will be separated into 15 tiers, therefore 15 unique IDs
     */
    uint256 public constant TIER1 = 1;
    uint256 public constant TIER2 = 2;
    uint256 public constant TIER3 = 3;
    uint256 public constant TIER4 = 4;
    uint256 public constant TIER5 = 5;
    uint256 public constant TIER6 = 6;
    uint256 public constant TIER7 = 7;
    uint256 public constant TIER8 = 8;
    uint256 public constant TIER9 = 9;
    uint256 public constant TIER10 = 10;
    uint256 public constant TIER11 = 11;
    uint256 public constant TIER12 = 12;
    uint256 public constant TIER13 = 13;
    uint256 public constant TIER14 = 14;
    uint256 public constant TIER15 = 15;

    string public _uri;

    //
    // PRIVATE STATE VARIABLES
    //

    // TODO Check if necessary
    //   string private _baseURI;

    address private bloomReferral;

    //
    // MODIFIERS
    //

    modifier onlyBloomReferral() {
        require(_msgSender() == bloomReferral, "Not approved");

        _;
    }

    modifier onlyExistingId(uint256 _tokenId) {
        require(_tokenId >= TIER1 && _tokenId <= TIER15, "Invalid token ID");

        _;
    }

    //
    // EXTERNAL FUNCTIONS
    //

    /**
     * @dev - Initializes this and other necessary contracts
     * @param uri_ - URI of all the token types, the only difference being the concatenated IDs of different tokens
     * @notice - Can only be initialized once
     */
    function initialize(string memory uri_, address _bloomReferral)
        external
        initializer
    {
        __Ownable_init();
        __ERC1155_init(uri_);
        __ERC1155URIStorage_init();

        bloomReferral = _bloomReferral;
    }

    /**
     * @dev - Mint function, which calls _beforeTokenTransfer to check if the user is already an owner
     * @param _to - Address of the user
     * @param _tokenId - ID of the token the user wants
     * @notice - Any account other than the deployer can only have one type of token at a time
     */
    function mint(address _to, uint256 _tokenId)
        external
        nonReentrant
        onlyBloomReferral
        onlyExistingId(_tokenId)
    {
        _beforeTokenTransfer(_to);

        _mint(_to, _tokenId, 1, "");
    }

    /**
     * @dev - Mint batch function, mints specified amounts of tokens of specified token ids
     * @param _to - Address of the wallet to mint to
     * @param _ids - IDs of the tokens to be minted, IDs have to be between TIER1 and TIER15
     * @param _amounts - Amounts of tokens of a certain ID to be minted
     * @param _data - Optional data to be passed to the function
     * @notice - Mints _amounts[i] of _ids[i] in the specified order of both arrays
     */
    function mintBatch(
        address _to,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        bytes memory _data
    ) external onlyOwner {
        for (uint256 i = 0; i < _ids.length; i++) {
            if (_ids[i] < TIER1 || _ids[i] > TIER15) {
                revert("Invalid ID");
            }
        }
        _mintBatch(_to, _ids, _amounts, _data);
    }

    /**
     * @dev - Burn function, burns amount of tokens of specified ID, from the specified address
     * @param _from - Address of the wallet from which to burn tokens
     * @param _tokenId - ID of the token to be burned
     * @param _amount - Amount of tokens of a certain ID to be burned
     * @notice - Address _from has to either be _msgSender(), or _msgSender() has to have previously been approved by _from
     */
    function burn(
        address _from,
        uint256 _tokenId,
        uint256 _amount
    ) external nonReentrant onlyExistingId(_tokenId) {
        require(
            _from == _msgSender() || isApprovedForAll(_from, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );

        _burn(_from, _tokenId, _amount);
    }

    /**
     * @dev - Burn batch function, burns specified amounts of tokens of specified token ids
     * @param _from - Address of the wallet from which to burn tokens
     * @param _ids - IDs of the tokens to be burned, IDs have to be between TIER1 and TIER15
     * @param _amounts - Amount of tokens of a certain ID to be burned
     * @notice - Burns _amounts[i] of _ids[i] in the specified order of both arrays
     */
    function burnBatch(
        address _from,
        uint256[] memory _ids,
        uint256[] memory _amounts
    ) external onlyOwner {
        for (uint256 i = 0; i < _ids.length; i++) {
            if (_ids[i] < TIER1 || _ids[i] > TIER15) {
                revert("Invalid ID");
            }
        }

        _burnBatch(_from, _ids, _amounts);
    }

    //
    // OWNER FUNCTIONS
    //

    /**
     * @dev - Sets bloomReferral address to another contract
     * @param _newBloomReferral - Address of the newly deployed BloomReferral contract
     */
    function setBloomReferral(address _newBloomReferral) external onlyOwner {
        bloomReferral = _newBloomReferral;
    }

    //
    // OPTIONAL OWNER FUNCTIONS
    //

    /**
     * @dev - BaseURI is optinal in ERC1155, since the already existing _uri can be used for all the tokens
     * @param baseURI_ - BaseURI for all of the tokens
     * @notice - Setting this enables each token to have different URIs
     */
    function setBaseURI(string memory baseURI_) external onlyOwner {
        _setBaseURI(baseURI_);
    }

    /**
     * @dev - This function sets tokenURI of _tokenId to _tokenURI
     * @param _tokenId - ID of the token whose tokenURI we want to set
     * @param _tokenURI - TokenURI we want to set for the _tokenId
     * @notice - ERC1155URIStorageUpgradeable contract has an uri function which concatenates baseURI and tokenURI if the two are set
     *         - This enables each token to have their own unique URIs, which aren't necessary
     */
    function setURI(uint256 _tokenId, string memory _tokenURI)
        external
        onlyOwner
    {
        _setURI(_tokenId, _tokenURI);
    }

    //
    // PRIVATE FUNCTIONS
    //

    /**
     * @dev - This function checks if the user previously owned any type of token, if so it burns the previously owned token
     * @param _sender - Address of the user who wants to mint a token
     * @notice - Deployer of this contract can own more than one token
     */
    function _beforeTokenTransfer(address _sender) private {
        if (_sender != owner()) {
            for (uint256 i = 1; i < 16; i++) {
                if (balanceOf(_sender, i) > 0) {
                    _burn(_sender, i, 1);
                }
            }
        }
    }
}
