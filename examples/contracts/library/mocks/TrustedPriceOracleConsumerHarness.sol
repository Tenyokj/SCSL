// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {
    TrustedPriceOracleConsumer,
    ITrustedPriceOracle
} from "../../../../library/oracle/TrustedPriceOracleConsumer.sol";

contract TrustedPriceOracleConsumerHarness is TrustedPriceOracleConsumer {
    constructor(address initialOwner, address initialOracle)
        TrustedPriceOracleConsumer(initialOwner, initialOracle)
    {}

    function readPrice() external view returns (uint256) {
        return _readTrustedPrice();
    }
}

contract MockTrustedPriceOracle is ITrustedPriceOracle {
    uint256 private currentPrice;

    constructor(uint256 initialPrice) {
        currentPrice = initialPrice;
    }

    function setPrice(uint256 newPrice) external {
        currentPrice = newPrice;
    }

    function getPrice() external view returns (uint256) {
        return currentPrice;
    }
}
