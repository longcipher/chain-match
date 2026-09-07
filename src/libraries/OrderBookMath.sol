// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title OrderBookMath
 * @dev Library for mathematical operations used in the Cohort Order Book.
 *      Includes safe arithmetic, price calculations, and fill ratio computations.
 */
library OrderBookMath {
    uint256 internal constant PRICE_PRECISION = 1e18;
    uint256 internal constant AMOUNT_PRECISION = 1e18;
    uint256 internal constant FILL_RATIO_PRECISION = 1e18;

    /**
     * @dev Calculate quote amount (price * amount) with precision handling.
     * @param price The price in PRICE_PRECISION
     * @param amount The amount in AMOUNT_PRECISION
     * @return quoteAmount The quote amount in AMOUNT_PRECISION
     */
    function calculateQuoteAmount(uint256 price, uint256 amount) internal pure returns (uint256 quoteAmount) {
        unchecked {
            quoteAmount = (price * amount) / PRICE_PRECISION;
        }
    }

    /**
     * @dev Calculate fill ratio as a percentage.
     * @param filledAmount The filled amount
     * @param totalAmount The total amount
     * @return ratio The fill ratio in FILL_RATIO_PRECISION (1e18 = 100%)
     */
    function calculateFillRatio(uint256 filledAmount, uint256 totalAmount)
        internal
        pure
        returns (uint256 ratio)
    {
        if (totalAmount == 0) return 0;
        unchecked {
            ratio = (filledAmount * FILL_RATIO_PRECISION) / totalAmount;
        }
    }

    /**
     * @dev Calculate average price from multiple fills.
     * @param amounts Array of fill amounts
     * @param prices Array of fill prices
     * @return avgPrice The weighted average price
     */
    function calculateAveragePrice(uint256[] memory amounts, uint256[] memory prices)
        internal
        pure
        returns (uint256 avgPrice)
    {
        require(amounts.length == prices.length, "Length mismatch");
        if (amounts.length == 0) return 0;

        uint256 totalWeightedPrice;
        uint256 totalAmount;

        unchecked {
            for (uint256 i = 0; i < amounts.length; i++) {
                totalWeightedPrice += amounts[i] * prices[i];
                totalAmount += amounts[i];
            }
            avgPrice = totalAmount > 0 ? totalWeightedPrice / totalAmount : 0;
        }
    }

    /**
     * @dev Calculate proportional fill amount for a cohort.
     * @param cohortTotal The total amount in the cohort
     * @param cohortFilled The already filled amount in the cohort
     * @param requestedAmount The amount requested to fill
     * @return fillAmount The actual fill amount
     */
    function calculateProportionalFill(
        uint256 cohortTotal,
        uint256 cohortFilled,
        uint256 requestedAmount
    ) internal pure returns (uint256 fillAmount) {
        uint256 available = cohortTotal - cohortFilled;
        unchecked {
            fillAmount = requestedAmount > available ? available : requestedAmount;
        }
    }

    /**
     * @dev Calculate remaining amount after fill.
     * @param originalAmount The original order amount
     * @param filledAmount The already filled amount
     * @param newFillAmount The new fill amount
     * @return remainingAmount The remaining amount to be filled
     */
    function calculateRemainingAmount(
        uint256 originalAmount,
        uint256 filledAmount,
        uint256 newFillAmount
    ) internal pure returns (uint256 remainingAmount) {
        unchecked {
            uint256 totalFilled = filledAmount + newFillAmount;
            remainingAmount = totalFilled >= originalAmount ? 0 : originalAmount - totalFilled;
        }
    }

    /**
     * @dev Safe subtraction that returns 0 if underflow would occur.
     */
    function safeSub(uint256 a, uint256 b) internal pure returns (uint256 result) {
        unchecked {
            result = a >= b ? a - b : 0;
        }
    }

    /**
     * @dev Safe addition that reverts on overflow.
     */
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256 result) {
        unchecked {
            result = a + b;
            require(result >= a, "Overflow");
        }
    }

    /**
     * @dev Calculate spread between best bid and best ask.
     * @param bestBid The best bid price
     * @param bestAsk The best ask price
     * @return spread The spread
     */
    function calculateSpread(uint256 bestBid, uint256 bestAsk) internal pure returns (uint256 spread) {
        unchecked {
            spread = bestAsk > bestBid ? bestAsk - bestBid : 0;
        }
    }

    /**
     * @dev Calculate mid price between best bid and best ask.
     * @param bestBid The best bid price
     * @param bestAsk The best ask price
     * @return midPrice The mid price
     */
    function calculateMidPrice(uint256 bestBid, uint256 bestAsk) internal pure returns (uint256 midPrice) {
        unchecked {
            midPrice = (bestBid + bestAsk) / 2;
        }
    }
}
