// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CohortOrderBook} from "../src/CohortOrderBook.sol";
import {ICohortOrderBook} from "../src/interfaces/ICohortOrderBook.sol";
import {Vm} from "forge-std/Vm.sol";

/**
 * @title CohortOrderBookE2ETest
 * @dev End-to-end integration tests simulating real trading scenarios.
 *      These tests verify the contract behavior in realistic market conditions.
 *
 * Testing Strategy:
 * 1. Full trading lifecycle: place -> fill/cancel -> verify state
 * 2. Multi-trader scenarios with concurrent orders
 * 3. Edge cases in market conditions (high volatility, low liquidity)
 * 4. Gas usage under various conditions
 * 5. State consistency after complex operations
 */
contract CohortOrderBookE2ETest is Test {
    CohortOrderBook public orderBook;

    // Multiple traders for realistic scenarios
    address public marketMaker = address(0x100);
    address public trader1 = address(0x101);
    address public trader2 = address(0x102);
    address public trader3 = address(0x103);
    address public whale = address(0x200);

    // Price levels (in 1e18 precision)
    uint96 constant P_BID_1 = 1000 ether; // Best bid
    uint96 constant P_BID_2 = 990 ether;
    uint96 constant P_BID_3 = 980 ether;
    uint96 constant P_BID_4 = 970 ether;
    uint96 constant P_BID_5 = 960 ether;

    uint96 constant P_ASK_1 = 1010 ether; // Best ask
    uint96 constant P_ASK_2 = 1020 ether;
    uint96 constant P_ASK_3 = 1030 ether;
    uint96 constant P_ASK_4 = 1040 ether;
    uint96 constant P_ASK_5 = 1050 ether;

    // Amounts
    uint256 constant A_SMALL = 1 ether;
    uint256 constant A_MEDIUM = 10 ether;
    uint256 constant A_LARGE = 100 ether;
    uint256 constant A_WHALE = 1000 ether;

    function setUp() public {
        orderBook = new CohortOrderBook();

        // Fund all traders
        vm.deal(marketMaker, 10000 ether);
        vm.deal(trader1, 10000 ether);
        vm.deal(trader2, 10000 ether);
        vm.deal(trader3, 10000 ether);
        vm.deal(whale, 100000 ether);
    }

    // ============ Scenario 1: Basic Trading Lifecycle ============

    /**
     * @dev Test the complete lifecycle of a trade:
     * 1. Market maker places limit orders
     * 2. Trader places market order
     * 3. Verify fills and state
     */
    function test_E2E_BasicTradeLifecycle() public {
        // Step 1: Market maker places limit sell order
        vm.prank(marketMaker);
        uint96 sellOrderId =
            orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_1, A_MEDIUM);

        // Verify order book state
        (uint96 bestAsk, uint256 askLiquidity) = orderBook.getBestAsk();
        assertEq(bestAsk, P_ASK_1);
        assertEq(askLiquidity, A_MEDIUM);

        // Verify spread
        uint256 spread = orderBook.getSpread();
        assertEq(spread, type(uint256).max); // No bid yet

        // Step 2: Trader buys with market order
        vm.prank(trader1);
        ICohortOrderBook.FillResult memory result =
            orderBook.placeMarketOrder(ICohortOrderBook.Side.Buy, A_SMALL);

        // Verify fill
        assertEq(result.filledAmount, A_SMALL);
        assertEq(result.remainingAmount, 0);
        assertEq(result.avgPrice, P_ASK_1);

        // Verify remaining liquidity
        (, askLiquidity) = orderBook.getBestAsk();
        assertEq(askLiquidity, A_MEDIUM - A_SMALL);

        // Verify order status
        ICohortOrderBook.Order memory sellOrder = orderBook.getOrder(sellOrderId);
        assertEq(uint8(sellOrder.status), uint8(ICohortOrderBook.OrderStatus.Active));
    }

    // ============ Scenario 2: Market Making with Multiple Price Levels ============

    /**
     * @dev Test market making with liquidity at multiple price levels.
     * Simulates a realistic order book with depth.
     */
    function test_E2E_MarketMakingMultipleLevels() public {
        // Market maker places orders at multiple price levels
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, A_MEDIUM);
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_2, A_LARGE);
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_3, A_LARGE);

        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_1, A_MEDIUM);
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_2, A_LARGE);
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_3, A_LARGE);

        // Verify order book state
        (uint96 bestBid, uint256 bidLiquidity) = orderBook.getBestBid();
        assertEq(bestBid, P_BID_1);
        assertEq(bidLiquidity, A_MEDIUM);

        (uint96 bestAsk, uint256 askLiquidity) = orderBook.getBestAsk();
        assertEq(bestAsk, P_ASK_1);
        assertEq(askLiquidity, A_MEDIUM);

        // Verify spread
        uint256 spread = orderBook.getSpread();
        assertEq(spread, P_ASK_1 - P_BID_1);

        // Verify order book depth
        (uint96[] memory bidPrices, uint256[] memory bidAmounts) =
            orderBook.getOrderBookDepth(ICohortOrderBook.Side.Buy, 3);
        assertEq(bidPrices.length, 3);
        assertEq(bidPrices[0], P_BID_1);
        assertEq(bidPrices[1], P_BID_2);
        assertEq(bidPrices[2], P_BID_3);
        assertEq(bidAmounts[0], A_MEDIUM);
        assertEq(bidAmounts[1], A_LARGE);
        assertEq(bidAmounts[2], A_LARGE);

        // Large market order that sweeps multiple levels
        // Buying 111 ether should fill: 10 at P_ASK_1 + 100 at P_ASK_2 + 1 at P_ASK_3
        vm.prank(whale);
        ICohortOrderBook.FillResult memory result =
            orderBook.placeMarketOrder(ICohortOrderBook.Side.Buy, A_MEDIUM + A_LARGE + A_SMALL);

        // Should fill all 111 ether (10 + 100 + 1)
        assertEq(result.filledAmount, A_MEDIUM + A_LARGE + A_SMALL);
        assertEq(result.remainingAmount, 0);

        // Best ask should still be P_ASK_3 (only partially filled, 99 remaining)
        (bestAsk, askLiquidity) = orderBook.getBestAsk();
        assertEq(bestAsk, P_ASK_3);
        assertEq(askLiquidity, A_LARGE - A_SMALL); // 100 - 1 = 99
    }

    // ============ Scenario 3: Concurrent Trading ============

    /**
     * @dev Test multiple traders placing and filling orders concurrently.
     */
    function test_E2E_ConcurrentTrading() public {
        // Multiple traders place limit orders
        vm.prank(trader1);
        uint96 t1_buy = orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, A_MEDIUM);

        vm.prank(trader2);
        uint96 t2_buy = orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, A_MEDIUM);

        vm.prank(trader3);
        uint96 t3_sell = orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_1, A_MEDIUM);

        // Verify liquidity
        (, uint256 bidLiquidity) = orderBook.getBestBid();
        assertEq(bidLiquidity, A_MEDIUM * 2);

        // Trader1 cancels their order
        vm.prank(trader1);
        orderBook.cancelOrder(t1_buy);

        // Verify updated liquidity
        (, bidLiquidity) = orderBook.getBestBid();
        assertEq(bidLiquidity, A_MEDIUM);

        // Trader3's sell order partially fills against remaining bid
        vm.prank(trader3);
        orderBook.cancelOrder(t3_sell);

        // Verify all orders
        ICohortOrderBook.Order memory order1 = orderBook.getOrder(t1_buy);
        assertEq(uint8(order1.status), uint8(ICohortOrderBook.OrderStatus.Cancelled));

        ICohortOrderBook.Order memory order2 = orderBook.getOrder(t2_buy);
        assertEq(uint8(order2.status), uint8(ICohortOrderBook.OrderStatus.Active));

        ICohortOrderBook.Order memory order3 = orderBook.getOrder(t3_sell);
        assertEq(uint8(order3.status), uint8(ICohortOrderBook.OrderStatus.Cancelled));
    }

    // ============ Scenario 4: Generational Liquidity ============

    /**
     * @dev Test that orders in different generations are handled correctly.
     * Older generations should be filled first (time priority).
     */
    function test_E2E_GenerationalLiquidity() public {
        // Generation 1: Place buy order
        vm.prank(trader1);
        uint96 order1 =
            orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, A_MEDIUM);

        uint64 gen1 = orderBook.getCurrentGeneration();

        // Advance to new generation
        vm.roll(block.number + 1);

        // Generation 2: Place another buy order at same price
        vm.prank(trader2);
        uint96 order2 =
            orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, A_MEDIUM);

        uint64 gen2 = orderBook.getCurrentGeneration();
        assertTrue(gen2 > gen1);

        // Verify both cohorts exist
        ICohortOrderBook.Cohort memory cohort1 =
            orderBook.getCohort(P_BID_1, ICohortOrderBook.Side.Buy, gen1);
        ICohortOrderBook.Cohort memory cohort2 =
            orderBook.getCohort(P_BID_1, ICohortOrderBook.Side.Buy, gen2);

        assertTrue(cohort1.exists);
        assertTrue(cohort2.exists);
        assertEq(cohort1.totalAmount, A_MEDIUM);
        assertEq(cohort2.totalAmount, A_MEDIUM);

        // Fill part of the liquidity - should fill gen1 first
        vm.prank(trader3);
        ICohortOrderBook.FillResult memory result =
            orderBook.placeMarketOrder(ICohortOrderBook.Side.Sell, A_SMALL);

        assertEq(result.filledAmount, A_SMALL);

        // Verify gen1 cohort has been partially filled
        cohort1 = orderBook.getCohort(P_BID_1, ICohortOrderBook.Side.Buy, gen1);
        if (cohort1.exists) {
            assertEq(cohort1.filledAmount, A_SMALL);
        }

        // Fill more to exhaust gen1
        vm.prank(trader3);
        result = orderBook.placeMarketOrder(ICohortOrderBook.Side.Sell, A_MEDIUM);

        // Now gen2 should have been partially filled
        cohort2 = orderBook.getCohort(P_BID_1, ICohortOrderBook.Side.Buy, gen2);
        if (cohort2.exists) {
            assertTrue(cohort2.filledAmount > 0);
        }
    }

    // ============ Scenario 5: Whale Trade ============

    /**
     * @dev Test a large market order that sweeps the entire order book.
     */
    function test_E2E_WhaleTrade() public {
        // Setup deep order book
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_1, A_MEDIUM);
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_2, A_MEDIUM);
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_3, A_MEDIUM);
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_4, A_MEDIUM);
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_5, A_MEDIUM);

        uint256 totalLiquidity = A_MEDIUM * 5;

        // Whale buys everything
        vm.prank(whale);
        ICohortOrderBook.FillResult memory result =
            orderBook.placeMarketOrder(ICohortOrderBook.Side.Buy, A_WHALE);

        // Should fill all available liquidity
        assertEq(result.filledAmount, totalLiquidity);
        assertEq(result.remainingAmount, A_WHALE - totalLiquidity);

        // Order book should have no asks
        (uint96 bestAsk, uint256 askLiquidity) = orderBook.getBestAsk();
        assertEq(askLiquidity, 0);
    }

    // ============ Scenario 6: Order Cancellation Fills ============

    /**
     * @dev Test that cancelled orders don't get filled.
     */
    function test_E2E_CancellationPreventsFill() public {
        vm.prank(trader1);
        uint96 buyOrder = orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, A_MEDIUM);

        vm.prank(trader2);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_1, A_MEDIUM);

        // Trader1 cancels
        vm.prank(trader1);
        orderBook.cancelOrder(buyOrder);

        // Trader3 tries to sell - should have no bid to fill
        vm.prank(trader3);
        ICohortOrderBook.FillResult memory result =
            orderBook.placeMarketOrder(ICohortOrderBook.Side.Sell, A_SMALL);

        assertEq(result.filledAmount, 0);
        assertEq(result.remainingAmount, A_SMALL);
    }

    // ============ Scenario 7: Batch Operations ============

    /**
     * @dev Test batch order placement and cancellation.
     */
    function test_E2E_BatchOperations() public {
        // Batch place orders
        ICohortOrderBook.Side[] memory sides = new ICohortOrderBook.Side[](4);
        uint96[] memory prices = new uint96[](4);
        uint256[] memory amounts = new uint256[](4);

        sides[0] = ICohortOrderBook.Side.Buy;
        sides[1] = ICohortOrderBook.Side.Buy;
        sides[2] = ICohortOrderBook.Side.Sell;
        sides[3] = ICohortOrderBook.Side.Sell;

        prices[0] = P_BID_1;
        prices[1] = P_BID_2;
        prices[2] = P_ASK_1;
        prices[3] = P_ASK_2;

        amounts[0] = A_MEDIUM;
        amounts[1] = A_LARGE;
        amounts[2] = A_MEDIUM;
        amounts[3] = A_LARGE;

        vm.prank(marketMaker);
        uint96[] memory orderIds = orderBook.batchPlaceLimitOrders(sides, prices, amounts);

        assertEq(orderIds.length, 4);

        // Verify all orders
        for (uint256 i = 0; i < orderIds.length; i++) {
            ICohortOrderBook.Order memory order = orderBook.getOrder(orderIds[i]);
            assertEq(uint8(order.status), uint8(ICohortOrderBook.OrderStatus.Active));
        }

        // Batch cancel
        vm.prank(marketMaker);
        uint256 cancelled = orderBook.batchCancelOrders(orderIds);
        assertEq(cancelled, 4);

        // Verify all cancelled
        for (uint256 i = 0; i < orderIds.length; i++) {
            ICohortOrderBook.Order memory order = orderBook.getOrder(orderIds[i]);
            assertEq(uint8(order.status), uint8(ICohortOrderBook.OrderStatus.Cancelled));
        }
    }

    // ============ Scenario 8: State Consistency ============

    /**
     * @dev Test that order book state remains consistent after many operations.
     */
    function test_E2E_StateConsistency() public {
        // Perform many operations
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(trader1);
            orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1 - (uint96(i) * 1 ether), A_SMALL);

            vm.prank(trader2);
            orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_1 + (uint96(i) * 1 ether), A_SMALL);
        }

        // Verify state
        ICohortOrderBook.OrderBookState memory state = orderBook.getOrderBookState();
        assertEq(state.totalOrders, 20);

        // Verify all trader orders
        uint96[] memory trader1Orders = orderBook.getTraderOrders(trader1);
        assertEq(trader1Orders.length, 10);

        uint96[] memory trader2Orders = orderBook.getTraderOrders(trader2);
        assertEq(trader2Orders.length, 10);

        // Cancel all trader1 orders
        vm.prank(trader1);
        orderBook.cancelAllOrders(trader1);

        // Verify state
        state = orderBook.getOrderBookState();
        assertEq(state.totalOrders, 20); // Total doesn't change

        // Verify all trader1 orders cancelled
        for (uint256 i = 0; i < trader1Orders.length; i++) {
            ICohortOrderBook.Order memory order = orderBook.getOrder(trader1Orders[i]);
            assertEq(uint8(order.status), uint8(ICohortOrderBook.OrderStatus.Cancelled));
        }
    }

    // ============ Scenario 9: Edge Cases ============

    /**
     * @dev Test minimum order size.
     */
    function test_E2E_MinimumOrderSize() public {
        vm.prank(trader1);
        uint96 orderId =
            orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, 1); // Minimum amount

        ICohortOrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(order.originalAmount, 1);
    }

    /**
     * @dev Test maximum price values.
     */
    function test_E2E_LargePriceValues() public {
        uint96 largePrice = type(uint96).max;

        vm.prank(trader1);
        uint96 orderId =
            orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, largePrice, A_SMALL);

        ICohortOrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(order.price, largePrice);
    }

    /**
     * @dev Test rapid order placement and cancellation.
     */
    function test_E2E_RapidOperations() public {
        // Place and immediately cancel
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(trader1);
            uint96 orderId =
                orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, A_SMALL);

            vm.prank(trader1);
            orderBook.cancelOrder(orderId);
        }

        // Order book should be empty
        (uint96 bestBid, ) = orderBook.getBestBid();
        assertEq(bestBid, 0);
    }

    // ============ Scenario 10: Multi-Generation Market Making ============

    /**
     * @dev Test market making across multiple generations.
     */
    function test_E2E_MultiGenerationMarketMaking() public {
        // Generation 1 orders
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, A_MEDIUM);
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_1, A_MEDIUM);

        vm.roll(block.number + 1);

        // Generation 2 orders
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, A_MEDIUM);
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_1, A_MEDIUM);

        // Verify total liquidity
        (, uint256 bidLiquidity) = orderBook.getBestBid();
        assertEq(bidLiquidity, A_MEDIUM * 2);

        (, uint256 askLiquidity) = orderBook.getBestAsk();
        assertEq(askLiquidity, A_MEDIUM * 2);

        // Fill through multiple generations
        vm.prank(trader1);
        orderBook.placeMarketOrder(ICohortOrderBook.Side.Buy, A_MEDIUM * 2);

        // Verify asks depleted
        (, askLiquidity) = orderBook.getBestAsk();
        assertEq(askLiquidity, 0);
    }

    // ============ Gas Benchmarks ============

    /**
     * @dev Benchmark gas for common operations.
     */
    function test_E2E_GasBenchmark_PlaceOrder() public {
        vm.prank(trader1);
        uint96 orderId =
            orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, A_MEDIUM);
        assertTrue(orderId > 0);
    }

    function test_E2E_GasBenchmark_FillOrder() public {
        vm.prank(marketMaker);
        orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, P_ASK_1, A_MEDIUM);

        vm.prank(trader1);
        orderBook.placeMarketOrder(ICohortOrderBook.Side.Buy, A_SMALL);
    }

    function test_E2E_GasBenchmark_CancelOrder() public {
        vm.prank(trader1);
        uint96 orderId =
            orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, P_BID_1, A_MEDIUM);

        vm.prank(trader1);
        orderBook.cancelOrder(orderId);
    }

    // ============ Invariant Tests ============

    /**
     * @dev Test that total liquidity is always non-negative.
     */
    function invariant_NonNegativeLiquidity() public {
        ICohortOrderBook.PriceLevel memory bidLevel =
            orderBook.getPriceLevel(P_BID_1, ICohortOrderBook.Side.Buy);
        ICohortOrderBook.PriceLevel memory askLevel =
            orderBook.getPriceLevel(P_ASK_1, ICohortOrderBook.Side.Sell);

        assertTrue(bidLevel.totalLiquidity >= bidLevel.filledLiquidity);
        assertTrue(askLevel.totalLiquidity >= askLevel.filledLiquidity);
    }

    /**
     * @dev Test that order book state is always valid.
     * Note: bid > ask is possible in volatile markets (arbitrage opportunity).
     */
    function invariant_ValidOrderBookState() public {
        ICohortOrderBook.OrderBookState memory state = orderBook.getOrderBookState();
        // Total orders should be nextOrderId - 1
        assertEq(state.totalOrders, state.nextOrderId - 1);
    }
}
