// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICohortOrderBook
 * @dev Interface for the Cohort Order Book - an O(1) fully on-chain limit order book
 *      via generational fungible liquidity.
 *
 * The key insight: instead of tracking individual orders, liquidity is grouped into
 * "cohorts" at each price level. All orders placed at the same price level within
 * the same generation are fungible - they share fills proportionally.
 *
 * This enables:
 * - O(1) order placement (just update cohort totals)
 * - O(1) order cancellation (just update cohort totals)
 * - O(1) matching (fill entire cohorts at once)
 */
interface ICohortOrderBook {
    // ============ Enums ============

    enum OrderType {
        Limit,
        Market
    }

    enum Side {
        Buy,
        Sell
    }

    enum OrderStatus {
        None,
        Active,
        PartiallyFilled,
        Filled,
        Cancelled
    }

    // ============ Structs ============

    struct Order {
        uint96 orderId;
        address trader;
        uint96 price;
        uint256 originalAmount;
        uint256 filledAmount;
        uint64 generation;
        Side side;
        OrderStatus status;
        uint48 createdAt;
    }

    struct Cohort {
        uint256 totalAmount;
        uint256 filledAmount;
        uint256 orderCount;
        uint64 generation;
        bool exists;
    }

    struct PriceLevel {
        uint256 totalLiquidity;
        uint256 filledLiquidity;
        uint256 cohortCount;
        bool exists;
    }

    struct Generation {
        uint64 currentGeneration;
        uint48 lastUpdateBlock;
    }

    struct OrderBookState {
        uint96 nextOrderId;
        uint96 nextPriceLevelId;
        uint64 currentGeneration;
        uint256 bestBid;
        uint256 bestAsk;
        uint256 totalOrders;
    }

    struct Trade {
        uint96 orderId;
        address trader;
        address counterparty;
        uint96 price;
        uint256 amount;
        uint256 quoteAmount;
        Side side;
        uint48 timestamp;
    }

    struct FillResult {
        uint256 filledAmount;
        uint256 remainingAmount;
        uint256 avgPrice;
        uint256 totalQuoteAmount;
        Trade[] trades;
    }

    // ============ Events ============

    event OrderPlaced(
        uint96 indexed orderId,
        address indexed trader,
        Side side,
        uint96 price,
        uint256 amount,
        uint64 generation
    );

    event OrderCancelled(uint96 indexed orderId, address indexed trader, uint256 remainingAmount);

    event OrderFilled(
        uint96 indexed orderId,
        address indexed trader,
        uint96 price,
        uint256 amount,
        uint64 generation
    );

    event CohortUpdated(
        uint96 indexed price,
        Side side,
        uint64 indexed generation,
        uint256 totalAmount,
        uint256 filledAmount
    );

    event TradeExecuted(
        uint96 indexed orderId,
        address indexed trader,
        address indexed counterparty,
        uint96 price,
        uint256 amount,
        Side side
    );

    event GenerationAdvanced(uint64 indexed newGeneration, uint48 blockNumber);

    event PriceLevelAdded(uint96 indexed price, Side side);

    // ============ Errors ============

    error InvalidPrice();
    error InvalidAmount();
    error OrderNotFound();
    error OrderNotActive();
    error UnauthorizedCancellation();
    error InsufficientLiquidity();
    error InvalidGeneration();
    error PriceLevelDoesNotExist();
    error CohortDoesNotExist();
    error AlreadyInitialized();
    error NotInitialized();
    error ReentrancyGuard();

    // ============ View Functions ============

    function getOrder(uint96 orderId) external view returns (Order memory);

    function getBestBid() external view returns (uint96 price, uint256 liquidity);

    function getBestAsk() external view returns (uint96 price, uint256 liquidity);

    function getPriceLevel(uint96 price, Side side) external view returns (PriceLevel memory);

    function getCohort(uint96 price, Side side, uint64 generation) external view returns (Cohort memory);

    function getSpread() external view returns (uint256);

    function getMidPrice() external view returns (uint256);

    function getOrderBookDepth(Side side, uint256 levels)
        external
        view
        returns (uint96[] memory prices, uint256[] memory liquidity);

    function getTraderOrders(address trader) external view returns (uint96[] memory);

    function getActiveGenerations(uint96 price, Side side) external view returns (uint64[] memory);

    function getGenerationFillRatio(uint96 price, Side side, uint64 generation)
        external
        view
        returns (uint256 numerator, uint256 denominator);

    function getCurrentGeneration() external view returns (uint64);

    function getOrderBookState() external view returns (OrderBookState memory);

    // ============ State-Changing Functions ============

    function placeLimitOrder(Side side, uint96 price, uint256 amount)
        external
        returns (uint96 orderId);

    function placeMarketOrder(Side side, uint256 amount)
        external
        returns (FillResult memory result);

    function cancelOrder(uint96 orderId) external;

    function cancelAllOrders(address trader) external returns (uint256 cancelledCount);

    function cancelOrdersBySide(address trader, Side side) external returns (uint256 cancelledCount);

    function cancelOrdersByPrice(address trader, uint96 price, Side side)
        external
        returns (uint256 cancelledCount);

    // ============ Admin Functions ============

    function advanceGeneration() external;

    function emergencyCancel(uint96 orderId) external;

    // ============ Batch Operations ============

    function batchPlaceLimitOrders(
        Side[] calldata sides,
        uint96[] calldata prices,
        uint256[] calldata amounts
    ) external returns (uint96[] memory orderIds);

    function batchCancelOrders(uint96[] calldata orderIds) external returns (uint256 cancelledCount);
}
