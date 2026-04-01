// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {TwoStepOwnable} from "../access/TwoStepOwnable.sol";

interface ITrustedPriceOracle {
    function getPrice() external view returns (uint256);
}

/// @title TrustedPriceOracleConsumer
/// @author SCSL
/// @notice Base contract for systems that must rely on a dedicated trusted oracle.
abstract contract TrustedPriceOracleConsumer is TwoStepOwnable {
    address private trustedPriceOracle;

    error TrustedPriceOracleInvalidAddress(address oracle);
    error TrustedPriceOracleInvalidValue(uint256 price);

    event TrustedPriceOracleUpdated(address indexed previousOracle, address indexed newOracle);

    constructor(address initialOwner, address initialOracle) TwoStepOwnable(initialOwner) {
        _setTrustedPriceOracle(initialOracle);
    }

    function priceOracle() public view returns (address) {
        return trustedPriceOracle;
    }

    function setPriceOracle(address newOracle) external onlyOwner {
        _setTrustedPriceOracle(newOracle);
    }

    function _readTrustedPrice() internal view returns (uint256 price) {
        price = ITrustedPriceOracle(trustedPriceOracle).getPrice();
        if (price == 0) {
            revert TrustedPriceOracleInvalidValue(0);
        }
    }

    function _setTrustedPriceOracle(address newOracle) internal {
        if (newOracle == address(0)) {
            revert TrustedPriceOracleInvalidAddress(address(0));
        }

        address previousOracle = trustedPriceOracle;
        trustedPriceOracle = newOracle;

        emit TrustedPriceOracleUpdated(previousOracle, newOracle);
    }
}
