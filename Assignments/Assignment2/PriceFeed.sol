// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./interfaces/IPriceFeed.sol";
import "./interfaces/AggregatorV3Interface.sol";

// Price feed smart contract
contract PriceFeed is IPriceFeed {
    AggregatorV3Interface internal priceFeed;

    /**
     * Creates an aggregator for the specified address on the Goerli testnet.
     */
    constructor(address priceFeedAddress) {
        priceFeed = AggregatorV3Interface(priceFeedAddress);
    }

    /**
     * Returns the latest price.
     */
    function getLatestPrice() external view override returns (int256, uint256) {
        (
            /* uint80 roundID */,
            int256 price,
            /* uint256 startedAt */,
            uint256 timestamp,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();
        return (price, timestamp);
    }
}
