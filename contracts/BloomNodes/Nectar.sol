// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./access/Whitelist.sol";
import "./OwnerRecoveryUpgradeable.sol";
import "./implementations/LiquidityPoolManagerImplementationPointerUpgradeable.sol";
import "./implementations/WalletObserverImplementationPointer.sol";

contract Nectar is
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    OwnerRecoveryUpgradeable,
    LiquidityPoolManagerImplementationPointerUpgradeable,
    WalletObserverImplementationPointer,
    ReentrancyGuardUpgradeable,
    Whitelist
{
    using SafeMathUpgradeable for uint256;

    struct Stats {
        uint256 txs;
        uint256 minted;
    }

    address public devWallet = 0x1981d1dd51f51f7Ffc16Dd13d69bFFBA942dACCe;
    address public vaultAddress;
    address public flowerManager;
    uint256 public constant MAX_INT = 2**256 - 1;
    uint256 public constant TARGET_SUPPLY = MAX_INT;
    uint256 public totalTxs;
    uint256 public players;
    bool public swapEnabled = false;
    bool public mintingFinished = false;

    mapping(address => Stats) private stats;
    mapping(address => uint8) private _customTaxRate;
    mapping(address => bool) private _hasCustomTax;
    mapping(address => bool) private _isExcluded;

    address[] private _excluded;
    uint256 private mintedSupply_;

    uint8 internal constant TAX_DEFAULT = 10; // 10% tax on transfers

    event SetSellFee(uint256 newSellFee);
    event SetTransferFee(uint256 newTransferFee);
    event SwapEnabled();
    event MintingFinished();

    modifier canMint() {
        require(!mintingFinished, "Minting is finished");
        _;
    }

    modifier onlyFlowerManager() {
        address sender = _msgSender();
        require(
            sender == address(flowerManager),
            "Implementations: Not FlowerManager"
        );
        _;
    }

    function initialize(address _flowerManager, uint256 _initialSupply)
        external
        initializer
    {
        require(
            _flowerManager != address(0),
            "Implementations: flowerManager is not set"
        );
        flowerManager = _flowerManager;
        __Ownable_init();
        __ERC20_init("Nectar", "NCTR");
        _mint(_msgSender(), _initialSupply);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable) {
        super._beforeTokenTransfer(from, to, amount);
        if (address(walletObserver) != address(0)) {
            walletObserver.beforeTokenTransfer(_msgSender(), from, to, amount);
        }
    }

    function calculateTransactionTax(uint256 _value, uint8 _tax)
        internal
        pure
        returns (uint256 adjustedValue, uint256 taxAmount)
    {
        taxAmount = _value.mul(_tax).div(100);
        adjustedValue = _value.mul(SafeMathUpgradeable.sub(100, _tax)).div(100);
        return (adjustedValue, taxAmount);
    }

    // function _transfer(
    //     address from,
    //     address to,
    //     uint256 amount
    // ) internal override(ERC20Upgradeable) {
    //     require(from != address(0), "ERC20: transfer from the zero address");
    //     require(to != address(0), "ERC20: transfer to the zero address");
    //     if (from != flowerManager && to != flowerManager) {
    //         require(swapEnabled, "Swap is not enabled");
    //     }

    //     uint256 devFees;
    //     uint256 treasuryFees;
    //     if (to == liquidityPoolManager.getPair()) {
    //         devFees = amount.mul(sellDevFee).div(100);
    //         treasuryFees = amount.mul(sellTreasuryFee).div(100);
    //         amount = amount.sub(devFees).sub(treasuryFees);
    //         address treasuryAddress = liquidityPoolManager.getTreasuryAddress();
    //         super._transfer(from, treasuryAddress, treasuryFees);
    //         super._transfer(from, devWallet, devFees);
    //     } else {
    //         (uint256 adjustedAmount, ) = calculateTransferTaxes(
    //             msg.sender,
    //             amount
    //         );
    //         super._transfer(from, to, adjustedAmount);
    //     }
    // }

    function calculateTransferTaxes(address _from, uint256 _value)
        public
        view
        returns (uint256 adjustedValue, uint256 taxAmount)
    {
        adjustedValue = _value;
        taxAmount = 0;

        if (!_isExcluded[_from]) {
            uint8 taxPercent = TAX_DEFAULT; // set to default tax 10%

            // set custom tax rate if applicable
            if (_hasCustomTax[_from]) {
                taxPercent = _customTaxRate[_from];
            }

            (adjustedValue, taxAmount) = calculateTransactionTax(
                _value,
                taxPercent
            );
        }
        return (adjustedValue, taxAmount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable) {
        super._afterTokenTransfer(from, to, amount);
        if (address(liquidityPoolManager) != address(0)) {
            liquidityPoolManager.afterTokenTransfer(_msgSender());
        }
    }

    function burnNectar(address account, uint256 amount)
        external
        onlyFlowerManager
    {
        // Note: _burn will call _beforeTokenTransfer which will ensure no denied addresses can create cargos
        // effectively protecting flowerManager from suspicious addresses
        super._burn(account, amount);
    }

    function mintNectar(address account, uint256 amount)
        external
        onlyFlowerManager
    {
        require(
            address(liquidityPoolManager) != account,
            "ApeBloom: Use liquidityReward to reward liquidity"
        );
        super._mint(account, amount);
    }

    function liquidityReward(uint256 amount) external onlyFlowerManager {
        // require(
        //     address(liquidityPoolManager) != address(0),
        //     "Bloom: LiquidityPoolManager is not set"
        // );
        super._mint(vaultAddress, amount);
    }

    // Toggle swap function
    function toggleSwap() public onlyOwner {
        swapEnabled = true;
        emit SwapEnabled();
    }

    /**
     * @dev Function to mint tokens
     * @param _to The address that will receive the minted tokens.
     * @param _amount The amount of tokens to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(address _to, uint256 _amount)
        public
        onlyFlowerManager
        canMint
        nonReentrant
        returns (bool)
    {
        require(!mintingFinished, "Minting is finished");
        //Never fail, just don't mint if over
        if (_amount == 0 || mintedSupply_.add(_amount) > TARGET_SUPPLY) {
            return false;
        }

        //Mint
        mintedSupply_ = mintedSupply_.add(_amount);
        super._mint(_to, _amount);

        if (mintedSupply_ == TARGET_SUPPLY) {
            mintingFinished = true;
            emit MintingFinished();
        }

        /* Members */
        if (stats[_to].txs == 0) {
            players += 1;
        }

        stats[_to].txs += 1;
        stats[_to].minted += _amount;

        totalTxs += 1;

        return true;
    }

    /**
     * @dev Function to stop minting new tokens.
     * @return True if the operation was successful.
     */
    function finishMinting() public onlyFlowerManager canMint returns (bool) {
        mintingFinished = true;
        emit MintingFinished();
        return true;
    }

    function setVaultAddress(address _newVaultAddress) public onlyOwner {
        vaultAddress = _newVaultAddress;
    }


    function setDevWallet(address devWallet_) external onlyOwner {
        devWallet = devWallet_;
    }

    function setFlowerManager(address _newFlowerManager)
        external
        onlyFlowerManager
    {
        flowerManager = _newFlowerManager;
    }
}
