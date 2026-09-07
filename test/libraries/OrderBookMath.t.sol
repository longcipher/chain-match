// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {OrderBookMath} from "../../src/libraries/OrderBookMath.sol";

/**
 * @title OrderBookMathTest
 * @dev Tests for the OrderBookMath library.
 */
contract OrderBookMathTest is Test {
    using OrderBookMath for uint256;

    function test_CalculateQuoteAmount() public pure {
        uint256 price = 100 ether;
        uint256 amount = 10 ether;
        uint256 quoteAmount = OrderBookMath.calculateQuoteAmount(price, amount);
        assertEq(quoteAmount, 1000 ether);
    }

    function test_CalculateQuoteAmount_ZeroAmount() public pure {
        uint256 price = 100 ether;
        uint256 amount = 0;
        uint256 quoteAmount = OrderBookMath.calculateQuoteAmount(price, amount);
        assertEq(quoteAmount, 0);
    }

    function test_CalculateFillRatio() public pure {
        uint256 filled = 50 ether;
        uint256 total = 100 ether;
        uint256 ratio = OrderBookMath.calculateFillRatio(filled, total);
        assertEq(ratio, 0.5 ether); // 50% in 1e18 precision
    }

    function test_CalculateFillRatio_ZeroTotal() public pure {
        uint256 filled = 50 ether;
        uint256 total = 0;
        uint256 ratio = OrderBookMath.calculateFillRatio(filled, total);
        assertEq(ratio, 0);
    }

    function test_CalculateFillRatio_FullyFilled() public pure {
        uint256 filled = 100 ether;
        uint256 total = 100 ether;
        uint256 ratio = OrderBookMath.calculateFillRatio(filled, total);
        assertEq(ratio, 1 ether); // 100%
    }

    function test_CalculateAveragePrice() public pure {
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory prices = new uint256[](2);

        amounts[0] = 10 ether;
        amounts[1] = 10 ether;
        prices[0] = 100 ether;
        prices[1] = 200 ether;

        uint256 avgPrice = OrderBookMath.calculateAveragePrice(amounts, prices);
        assertEq(avgPrice, 150 ether);
    }

    function test_CalculateAveragePrice_SingleFill() public pure {
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory prices = new uint256[](1);

        amounts[0] = 10 ether;
        prices[0] = 100 ether;

        uint256 avgPrice = OrderBookMath.calculateAveragePrice(amounts, prices);
        assertEq(avgPrice, 100 ether);
    }

    function test_CalculateAveragePrice_Empty() public pure {
        uint256[] memory amounts = new uint256[](0);
        uint256[] memory prices = new uint256[](0);

        uint256 avgPrice = OrderBookMath.calculateAveragePrice(amounts, prices);
        assertEq(avgPrice, 0);
    }

    function test_CalculateProportionalFill() public pure {
        uint256 cohortTotal = 100 ether;
        uint256 cohortFilled = 50 ether;
        uint256 requested = 30 ether;

        uint256 fillAmount = OrderBookMath.calculateProportionalFill(cohortTotal, cohortFilled, requested);
        assertEq(fillAmount, 30 ether);
    }

    function test_CalculateProportionalFill_ExceedsAvailable() public pure {
        uint256 cohortTotal = 100 ether;
        uint256 cohortFilled = 80 ether;
        uint256 requested = 30 ether;

        uint256 fillAmount = OrderBookMath.calculateProportionalFill(cohortTotal, cohortFilled, requested);
        assertEq(fillAmount, 20 ether); // Only 20 available
    }

    function test_CalculateProportionalFill_FullyFilled() public pure {
        uint256 cohortTotal = 100 ether;
        uint256 cohortFilled = 100 ether;
        uint256 requested = 30 ether;

        uint256 fillAmount = OrderBookMath.calculateProportionalFill(cohortTotal, cohortFilled, requested);
        assertEq(fillAmount, 0);
    }

    function test_CalculateRemainingAmount() public pure {
        uint256 original = 100 ether;
        uint256 filled = 50 ether;
        uint256 newFill = 30 ether;

        uint256 remaining = OrderBookMath.calculateRemainingAmount(original, filled, newFill);
        assertEq(remaining, 20 ether);
    }

    function test_CalculateRemainingAmount_FullyFilled() public pure {
        uint256 original = 100 ether;
        uint256 filled = 50 ether;
        uint256 newFill = 50 ether;

        uint256 remaining = OrderBookMath.calculateRemainingAmount(original, filled, newFill);
        assertEq(remaining, 0);
    }

    function test_CalculateRemainingAmount_Overfilled() public pure {
        uint256 original = 100 ether;
        uint256 filled = 50 ether;
        uint256 newFill = 60 ether;

        uint256 remaining = OrderBookMath.calculateRemainingAmount(original, filled, newFill);
        assertEq(remaining, 0); // Can't go negative
    }

    function test_SafeSub() public pure {
        uint256 result = OrderBookMath.safeSub(100, 50);
        assertEq(result, 50);
    }

    function test_SafeSub_Underflow() public pure {
        uint256 result = OrderBookMath.safeSub(50, 100);
        assertEq(result, 0); // Returns 0 on underflow
    }

    function test_SafeAdd() public pure {
        uint256 result = OrderBookMath.safeAdd(100, 50);
        assertEq(result, 150);
    }

    function test_CalculateSpread() public pure {
        uint256 spread = OrderBookMath.calculateSpread(100 ether, 110 ether);
        assertEq(spread, 10 ether);
    }

    function test_CalculateSpread_NoSpread() public pure {
        uint256 spread = OrderBookMath.calculateSpread(110 ether, 100 ether);
        assertEq(spread, 0); // Returns 0 when bid > ask
    }

    function test_CalculateMidPrice() public pure {
        uint256 midPrice = OrderBookMath.calculateMidPrice(100 ether, 110 ether);
        assertEq(midPrice, 105 ether);
    }

    function test_CalculateMidPrice_SamePrice() public pure {
        uint256 midPrice = OrderBookMath.calculateMidPrice(100 ether, 100 ether);
        assertEq(midPrice, 100 ether);
    }
}
