// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IMint.sol";
import "./sAsset.sol";
import "./EUSD.sol";

contract Mint is Ownable, IMint {
    struct Asset {
        address token;
        uint minCollateralRatio;
        address priceFeed;
    }

    struct Position {
        uint idx;
        address owner;
        uint collateralAmount;
        address assetToken;
        uint assetAmount;
    }

    mapping(address => Asset) _assetMap;
    uint _currentPositionIndex;
    mapping(uint => Position) _idxPositionMap;
    address public collateralToken;

    constructor(address collateral) {
        collateralToken = collateral;
    }

    function registerAsset(
        address assetToken,
        uint minCollateralRatio,
        address priceFeed
    ) external override onlyOwner {
        require(assetToken != address(0), "Invalid assetToken address");
        require(
            minCollateralRatio >= 1,
            "minCollateralRatio must be greater than 100%"
        );
        require(
            _assetMap[assetToken].token == address(0),
            "Asset was already registered"
        );

        _assetMap[assetToken] = Asset(
            assetToken,
            minCollateralRatio,
            priceFeed
        );
    }

    function getPosition(
        uint positionIndex
    ) external view returns (address, uint, address, uint) {
        require(positionIndex < _currentPositionIndex, "Invalid index");
        Position storage position = _idxPositionMap[positionIndex];
        return (
            position.owner,
            position.collateralAmount,
            position.assetToken,
            position.assetAmount
        );
    }

    function getMintAmount(
        uint collateralAmount,
        address assetToken,
        uint collateralRatio
    ) public view returns (uint) {
        Asset storage asset = _assetMap[assetToken];
        (int relativeAssetPrice, ) = IPriceFeed(asset.priceFeed)
            .getLatestPrice();
        uint8 decimal = sAsset(assetToken).decimals();
        uint mintAmount = (collateralAmount * (10 ** uint256(decimal))) /
            uint(relativeAssetPrice) /
            collateralRatio;
        return mintAmount;
    }

    function checkRegistered(address assetToken) public view returns (bool) {
        return _assetMap[assetToken].token == assetToken;
    }

    function openPosition(
        uint collateralAmount,
        address assetToken,
        uint collateralRatio
    ) external override {
        require(checkRegistered(assetToken), "Asset was not yet registered");
        require(
            collateralRatio >= _assetMap[assetToken].minCollateralRatio,
            "collateralRatio must not be less than the Asset's minCollateralRatio"
        );

        // Transfer the collateral from sender to contract.
        EUSD(collateralToken).transferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );

        // Send the appropriate number of minted tokens to the sender.
        uint assetAmount = getMintAmount(
            collateralAmount,
            assetToken,
            collateralRatio
        );
        sAsset(assetToken).mint(msg.sender, assetAmount);

        // Alter the position.
        _idxPositionMap[_currentPositionIndex] = Position(
            _currentPositionIndex,
            msg.sender,
            collateralAmount,
            assetToken,
            assetAmount
        );
        _currentPositionIndex += 1;
    }

    function closePosition(uint positionIndex) external override {
        require(positionIndex < _currentPositionIndex, "Invalid index");
        Position memory position = _idxPositionMap[positionIndex];
        require(position.owner == msg.sender, "You do not own this position");
        Asset memory asset = _assetMap[position.assetToken];

        // Burn all sAsset tokens.
        sAsset(asset.token).burn(msg.sender, position.assetAmount);

        // Transfer EUSD tokens back to the sender.
        EUSD(collateralToken).transfer(msg.sender, position.collateralAmount);

        // Clear the position at the index.
        delete _idxPositionMap[positionIndex];
    }

    function deposit(
        uint positionIndex,
        uint collateralAmount
    ) external override {
        require(positionIndex < _currentPositionIndex, "Invalid index");
        Position storage position = _idxPositionMap[positionIndex];
        require(position.owner == msg.sender, "You do not own this position");

        // Increase collateral by taking the amount from sender.
        EUSD(collateralToken).transferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );

        // Alter the position.
        position.collateralAmount += collateralAmount;
    }

    function withdraw(
        uint positionIndex,
        uint withdrawAmount
    ) external override {
        require(positionIndex < _currentPositionIndex, "Invalid index");
        Position storage position = _idxPositionMap[positionIndex];
        require(position.owner == msg.sender, "You do not own this position");
        Asset memory asset = _assetMap[position.assetToken];

        // Check for underflow.
        if (position.collateralAmount <= withdrawAmount) {
            withdrawAmount = position.collateralAmount;
        }
        uint newCollateralAmount = position.collateralAmount - withdrawAmount;

        // Make sure the collateral ratio doesn't go below the MCR.
        uint maxMintAmount = getMintAmount(
            newCollateralAmount,
            asset.token,
            asset.minCollateralRatio
        );
        require(
            position.assetAmount <= maxMintAmount,
            "Not enough collateral to withdraw the requested withdrawAmount"
        );

        // Transfer the tokens from the contract to the sender.
        EUSD(collateralToken).transfer(msg.sender, withdrawAmount);

        // Alter the position.
        position.collateralAmount = newCollateralAmount;
    }

    // Mints more asset tokens for this position.
    function mint(uint positionIndex, uint mintAmount) external override {
        require(positionIndex < _currentPositionIndex, "Invalid index");
        Position storage position = _idxPositionMap[positionIndex];
        require(position.owner == msg.sender, "You do not own this position");
        Asset memory asset = _assetMap[position.assetToken];

        // Make sure the collateral ratio doesn't go below the MCR.
        uint maxMintAmount = getMintAmount(
            position.collateralAmount,
            asset.token,
            asset.minCollateralRatio
        );
        uint newAssetAmount = position.assetAmount + mintAmount;
        require(
            newAssetAmount <= maxMintAmount,
            "Not enough collateral to mint the requested mintAmount"
        );

        sAsset(asset.token).mint(msg.sender, mintAmount);
        position.assetAmount = newAssetAmount;
    }

    function burn(uint positionIndex, uint burnAmount) external override {
        require(positionIndex < _currentPositionIndex, "Invalid index");
        Position storage position = _idxPositionMap[positionIndex];
        require(position.owner == msg.sender, "You do not own this position");
        Asset memory asset = _assetMap[position.assetToken];

        // Check for underflow.
        if (position.assetAmount <= burnAmount) {
            burnAmount = position.assetAmount;
        }
        uint newAssetAmount = position.assetAmount - burnAmount;

        sAsset(asset.token).burn(msg.sender, burnAmount);
        position.assetAmount = newAssetAmount;
    }
}
