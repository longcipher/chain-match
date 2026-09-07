// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICohortOrderBook} from "./interfaces/ICohortOrderBook.sol";
import {OrderBookMath} from "./libraries/OrderBookMath.sol";
import {PriceLevelTree} from "./libraries/PriceLevelTree.sol";
import {CohortManager} from "./libraries/CohortManager.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";

/**
 * @title CohortOrderBook
 * @dev An O(1) fully on-chain limit order book via generational fungible liquidity.
 *
 * KEY INSIGHT - Generational Fungible Liquidity:
 * Instead of tracking individual orders, liquidity is grouped into "cohorts" at each price level.
 * All orders placed at the same price level within the same generation are fungible - they share
 * fills proportionally based on their contribution to the cohort.
 *
 * This enables O(1) operations:
 * - Order placement: Just update cohort totals
 * - Order cancellation: Just update cohort totals
 * - Matching: Fill entire cohorts at once
 *
 * The generation counter advances periodically (e.g., per block or per batch), creating new
 * cohorts. This ensures that older liquidity gets filled first (time priority) while maintaining
 * O(1) operations.
 *
 * ARCHITECTURE:
 * - PriceLevelTree: Sorted doubly-linked list for O(1) best bid/ask access
 * - CohortManager: Manages cohorts at each price level
 * - Order tracking: Individual order records for trader reference
 */
contract CohortOrderBook is ICohortOrderBook, ReentrancyGuard {
    using PriceLevelTree for PriceLevelTree.Tree;
    using CohortManager for CohortManager.CohortStore;
    using OrderBookMath for uint256;

    // ============ Constants ============

    uint256 public constant MIN_PRICE = 1;
    uint256 public constant MAX_PRICE = type(uint96).max;
    uint256 public constant MIN_AMOUNT = 1;
    uint256 public constant MAX_AMOUNT = type(uint128).max;

    // ============ State Variables ============

    // Order tracking
    mapping(uint96 => Order) private _orders;
    mapping(address => uint96[]) private _traderOrders;
    mapping(address => mapping(uint96 => uint256)) private _traderOrderIndex;

    // Price level trees (sorted)
    PriceLevelTree.Tree private _bidTree;
    PriceLevelTree.Tree private _askTree;

    // Cohort stores for each side
    CohortManager.CohortStore private _bidCohorts;
    CohortManager.CohortStore private _askCohorts;

    // Generation tracking
    uint64 private _currentGeneration;
    uint48 private _lastGenerationBlock;

    // Order ID counter
    uint96 private _nextOrderId;

    // Best prices (cached for O(1) access)
    uint96 private _bestBid;
    uint96 private _bestAsk;

    // Admin
    address public owner;

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ============ Constructor ============

    constructor() {
        owner = msg.sender;
        _currentGeneration = 1;
        _nextOrderId = 1;
        _lastGenerationBlock = uint48(block.number);

        _bidTree.initialize();
        _askTree.initialize();
    }

    // ============ Receive Function ============

    receive() external payable {
        revert("Direct ETH not accepted");
    }

    // ============ View Functions ============

    /**
     * @dev Get order details by ID.
     */
    function getOrder(uint96 orderId) external view override returns (Order memory) {
        require(_orders[orderId].status != OrderStatus.None, OrderNotFound());
        return _orders[orderId];
    }

    /**
     * @dev Get the best bid price and its liquidity.
     */
    function getBestBid() external view override returns (uint96 price, uint256 liquidity) {
        if (_bestBid == 0) return (0, 0);
        price = _bestBid;
        liquidity = _bidCohorts.getAvailableLiquidity(_bestBid);
    }

    /**
     * @dev Get the best ask price and its liquidity.
     */
    function getBestAsk() external view override returns (uint96 price, uint256 liquidity) {
        if (_bestAsk == 0) return (0, 0);
        price = _bestAsk;
        liquidity = _askCohorts.getAvailableLiquidity(_bestAsk);
    }

    /**
     * @dev Get price level details.
     */
    function getPriceLevel(uint96 price, Side side) external view override returns (PriceLevel memory) {
        if (side == Side.Buy) {
            return _bidCohorts.getPriceLevel(price);
        } else {
            return _askCohorts.getPriceLevel(price);
        }
    }

    /**
     * @dev Get cohort details.
     */
    function getCohort(uint96 price, Side side, uint64 generation)
        external
        view
        override
        returns (Cohort memory)
    {
        if (side == Side.Buy) {
            return _bidCohorts.getCohort(price, generation);
        } else {
            return _askCohorts.getCohort(price, generation);
        }
    }

    /**
     * @dev Get the spread between best bid and best ask.
     */
    function getSpread() external view override returns (uint256) {
        if (_bestBid == 0 || _bestAsk == 0) return type(uint256).max;
        return OrderBookMath.calculateSpread(_bestBid, _bestAsk);
    }

    /**
     * @dev Get the mid price.
     */
    function getMidPrice() external view override returns (uint256) {
        if (_bestBid == 0 || _bestAsk == 0) return 0;
        return OrderBookMath.calculateMidPrice(_bestBid, _bestAsk);
    }

    /**
     * @dev Get order book depth for a side.
     */
    function getOrderBookDepth(Side side, uint256 levels)
        external
        view
        override
        returns (uint96[] memory prices, uint256[] memory liquidity)
    {
        PriceLevelTree.Tree storage tree = side == Side.Buy ? _bidTree : _askTree;
        CohortManager.CohortStore storage store = side == Side.Buy ? _bidCohorts : _askCohorts;

        prices = tree.getPrices(levels, side == Side.Buy);
        liquidity = new uint256[](prices.length);

        for (uint256 i = 0; i < prices.length; i++) {
            liquidity[i] = store.getAvailableLiquidity(prices[i]);
        }
    }

    /**
     * @dev Get all order IDs for a trader.
     */
    function getTraderOrders(address trader) external view override returns (uint96[] memory) {
        return _traderOrders[trader];
    }

    /**
     * @dev Get active generations for a price level.
     */
    function getActiveGenerations(uint96 price, Side side) external view override returns (uint64[] memory) {
        if (side == Side.Buy) {
            return _bidCohorts.getActiveGenerations(price);
        } else {
            return _askCohorts.getActiveGenerations(price);
        }
    }

    /**
     * @dev Get fill ratio for a specific cohort.
     */
    function getGenerationFillRatio(uint96 price, Side side, uint64 generation)
        external
        view
        override
        returns (uint256 numerator, uint256 denominator)
    {
        if (side == Side.Buy) {
            return _bidCohorts.getFillRatio(price, generation);
        } else {
            return _askCohorts.getFillRatio(price, generation);
        }
    }

    /**
     * @dev Get current generation number.
     */
    function getCurrentGeneration() external view override returns (uint64) {
        return _currentGeneration;
    }

    /**
     * @dev Get overall order book state.
     */
    function getOrderBookState() external view override returns (OrderBookState memory) {
        return OrderBookState({
            nextOrderId: _nextOrderId,
            nextPriceLevelId: 0,
            currentGeneration: _currentGeneration,
            bestBid: _bestBid,
            bestAsk: _bestAsk,
            totalOrders: _nextOrderId - 1
        });
    }

    // ============ Order Placement ============

    /**
     * @dev Place a limit order.
     * @param side Buy or Sell
     * @param price Order price
     * @param amount Order amount
     * @return orderId The ID of the placed order
     */
    function placeLimitOrder(Side side, uint96 price, uint256 amount)
        external
        override
        nonReentrant
        returns (uint96 orderId)
    {
        if (price < MIN_PRICE || price > MAX_PRICE) revert InvalidPrice();
        if (amount < MIN_AMOUNT || amount > MAX_AMOUNT) revert InvalidAmount();

        // Auto-advance generation if new block
        _autoAdvanceGeneration();

        // Generate order ID
        orderId = _nextOrderId;
        unchecked {
            _nextOrderId++;
        }

        // Store order
        _orders[orderId] = Order({
            orderId: orderId,
            trader: msg.sender,
            price: price,
            originalAmount: amount,
            filledAmount: 0,
            generation: _currentGeneration,
            side: side,
            status: OrderStatus.Active,
            createdAt: uint48(block.timestamp)
        });

        // Add to trader's orders
        _traderOrderIndex[msg.sender][orderId] = _traderOrders[msg.sender].length;
        _traderOrders[msg.sender].push(orderId);

        // Add to cohort
        if (side == Side.Buy) {
            _bidCohorts.addLiquidity(price, amount, _currentGeneration);
            if (!_bidTree.contains(price)) {
                _bidTree.insert(price, true);
                emit PriceLevelAdded(price, Side.Buy);
            }
        } else {
            _askCohorts.addLiquidity(price, amount, _currentGeneration);
            if (!_askTree.contains(price)) {
                _askTree.insert(price, false);
                emit PriceLevelAdded(price, Side.Sell);
            }
        }

        // Update best prices
        _updateBestPrices(side, price);

        emit OrderPlaced(orderId, msg.sender, side, price, amount, _currentGeneration);

        return orderId;
    }

    /**
     * @dev Place a market order (immediate execution).
     * @param side Buy or Sell
     * @param amount Order amount
     * @return result Fill result with details
     */
    function placeMarketOrder(Side side, uint256 amount)
        external
        override
        nonReentrant
        returns (FillResult memory result)
    {
        if (amount < MIN_AMOUNT) revert InvalidAmount();

        // Auto-advance generation
        _autoAdvanceGeneration();

        // Generate order ID for tracking
        uint96 orderId = _nextOrderId;
        unchecked {
            _nextOrderId++;
        }

        // Store order
        _orders[orderId] = Order({
            orderId: orderId,
            trader: msg.sender,
            price: 0,
            originalAmount: amount,
            filledAmount: 0,
            generation: _currentGeneration,
            side: side,
            status: OrderStatus.Active,
            createdAt: uint48(block.timestamp)
        });

        // Add to trader's orders
        _traderOrderIndex[msg.sender][orderId] = _traderOrders[msg.sender].length;
        _traderOrders[msg.sender].push(orderId);

        // Execute against opposite side
        if (side == Side.Buy) {
            result = _executeAgainstAsks(amount, orderId, msg.sender);
        } else {
            result = _executeAgainstBids(amount, orderId, msg.sender);
        }

        // Update order status
        if (result.remainingAmount == 0) {
            _orders[orderId].status = OrderStatus.Filled;
        } else if (result.filledAmount > 0) {
            _orders[orderId].status = OrderStatus.PartiallyFilled;
        }

        _orders[orderId].filledAmount = result.filledAmount;

        return result;
    }

    // ============ Order Cancellation ============

    /**
     * @dev Cancel an existing order.
     * @param orderId The order to cancel
     */
    function cancelOrder(uint96 orderId) external override nonReentrant {
        Order storage order = _orders[orderId];
        if (order.status == OrderStatus.None) revert OrderNotFound();
        if (order.status != OrderStatus.Active && order.status != OrderStatus.PartiallyFilled) {
            revert OrderNotActive();
        }
        if (order.trader != msg.sender) revert UnauthorizedCancellation();

        uint256 remainingAmount = order.originalAmount - order.filledAmount;

        // Remove from cohort
        if (order.side == Side.Buy) {
            _bidCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
            if (_bidCohorts.getAvailableLiquidity(order.price) == 0) {
                _bidTree.remove(order.price);
            }
        } else {
            _askCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
            if (_askCohorts.getAvailableLiquidity(order.price) == 0) {
                _askTree.remove(order.price);
            }
        }

        // Update order status
        order.status = OrderStatus.Cancelled;

        // Update best prices if needed
        if (order.price == _bestBid) _updateBestBid();
        if (order.price == _bestAsk) _updateBestAsk();

        emit OrderCancelled(orderId, msg.sender, remainingAmount);
    }

    /**
     * @dev Cancel all orders for a trader.
     */
    function cancelAllOrders(address trader) external override nonReentrant returns (uint256 cancelledCount) {
        uint96[] storage orders = _traderOrders[trader];

        for (uint256 i = 0; i < orders.length; i++) {
            uint96 orderId = orders[i];
            Order storage order = _orders[orderId];

            if (order.status == OrderStatus.Active || order.status == OrderStatus.PartiallyFilled) {
                if (order.trader == msg.sender) {
                    uint256 remainingAmount = order.originalAmount - order.filledAmount;

                    if (order.side == Side.Buy) {
                        _bidCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
                        if (_bidCohorts.getAvailableLiquidity(order.price) == 0) {
                            _bidTree.remove(order.price);
                        }
                    } else {
                        _askCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
                        if (_askCohorts.getAvailableLiquidity(order.price) == 0) {
                            _askTree.remove(order.price);
                        }
                    }

                    order.status = OrderStatus.Cancelled;
                    cancelledCount++;

                    emit OrderCancelled(orderId, trader, remainingAmount);
                }
            }
        }

        // Update best prices
        _updateBestBid();
        _updateBestAsk();
    }

    /**
     * @dev Cancel all orders for a trader on a specific side.
     */
    function cancelOrdersBySide(address trader, Side side)
        external
        override
        nonReentrant
        returns (uint256 cancelledCount)
    {
        uint96[] storage orders = _traderOrders[trader];

        for (uint256 i = 0; i < orders.length; i++) {
            uint96 orderId = orders[i];
            Order storage order = _orders[orderId];

            if (
                (order.status == OrderStatus.Active || order.status == OrderStatus.PartiallyFilled)
                    && order.side == side && order.trader == msg.sender
            ) {
                uint256 remainingAmount = order.originalAmount - order.filledAmount;

                if (order.side == Side.Buy) {
                    _bidCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
                    if (_bidCohorts.getAvailableLiquidity(order.price) == 0) {
                        _bidTree.remove(order.price);
                    }
                } else {
                    _askCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
                    if (_askCohorts.getAvailableLiquidity(order.price) == 0) {
                        _askTree.remove(order.price);
                    }
                }

                order.status = OrderStatus.Cancelled;
                cancelledCount++;

                emit OrderCancelled(orderId, trader, remainingAmount);
            }
        }

        // Update best prices
        _updateBestBid();
        _updateBestAsk();
    }

    /**
     * @dev Cancel all orders for a trader at a specific price and side.
     */
    function cancelOrdersByPrice(address trader, uint96 price, Side side)
        external
        override
        nonReentrant
        returns (uint256 cancelledCount)
    {
        uint96[] storage orders = _traderOrders[trader];

        for (uint256 i = 0; i < orders.length; i++) {
            uint96 orderId = orders[i];
            Order storage order = _orders[orderId];

            if (
                (order.status == OrderStatus.Active || order.status == OrderStatus.PartiallyFilled)
                    && order.side == side && order.price == price && order.trader == msg.sender
            ) {
                uint256 remainingAmount = order.originalAmount - order.filledAmount;

                if (order.side == Side.Buy) {
                    _bidCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
                    if (_bidCohorts.getAvailableLiquidity(order.price) == 0) {
                        _bidTree.remove(order.price);
                    }
                } else {
                    _askCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
                    if (_askCohorts.getAvailableLiquidity(order.price) == 0) {
                        _askTree.remove(order.price);
                    }
                }

                order.status = OrderStatus.Cancelled;
                cancelledCount++;

                emit OrderCancelled(orderId, trader, remainingAmount);
            }
        }

        // Update best prices
        _updateBestBid();
        _updateBestAsk();
    }

    // ============ Batch Operations ============

    /**
     * @dev Place multiple limit orders in a single transaction.
     */
    function batchPlaceLimitOrders(
        Side[] calldata sides,
        uint96[] calldata prices,
        uint256[] calldata amounts
    ) external override nonReentrant returns (uint96[] memory orderIds) {
        require(
            sides.length == prices.length && prices.length == amounts.length,
            "Length mismatch"
        );

        orderIds = new uint96[](sides.length);

        // Auto-advance generation once for the batch
        _autoAdvanceGeneration();

        for (uint256 i = 0; i < sides.length; i++) {
            if (prices[i] < MIN_PRICE || prices[i] > MAX_PRICE) revert InvalidPrice();
            if (amounts[i] < MIN_AMOUNT || amounts[i] > MAX_AMOUNT) revert InvalidAmount();

            uint96 orderId = _nextOrderId;
            unchecked {
                _nextOrderId++;
            }

            orderIds[i] = orderId;

            _orders[orderId] = Order({
                orderId: orderId,
                trader: msg.sender,
                price: prices[i],
                originalAmount: amounts[i],
                filledAmount: 0,
                generation: _currentGeneration,
                side: sides[i],
                status: OrderStatus.Active,
                createdAt: uint48(block.timestamp)
            });

            _traderOrderIndex[msg.sender][orderId] = _traderOrders[msg.sender].length;
            _traderOrders[msg.sender].push(orderId);

            if (sides[i] == Side.Buy) {
                _bidCohorts.addLiquidity(prices[i], amounts[i], _currentGeneration);
                if (!_bidTree.contains(prices[i])) {
                    _bidTree.insert(prices[i], true);
                    emit PriceLevelAdded(prices[i], Side.Buy);
                }
            } else {
                _askCohorts.addLiquidity(prices[i], amounts[i], _currentGeneration);
                if (!_askTree.contains(prices[i])) {
                    _askTree.insert(prices[i], false);
                    emit PriceLevelAdded(prices[i], Side.Sell);
                }
            }

            _updateBestPrices(sides[i], prices[i]);

            emit OrderPlaced(orderId, msg.sender, sides[i], prices[i], amounts[i], _currentGeneration);
        }
    }

    /**
     * @dev Cancel multiple orders in a single transaction.
     */
    function batchCancelOrders(uint96[] calldata orderIds)
        external
        override
        nonReentrant
        returns (uint256 cancelledCount)
    {
        for (uint256 i = 0; i < orderIds.length; i++) {
            uint96 orderId = orderIds[i];
            Order storage order = _orders[orderId];

            if (order.status == OrderStatus.None) continue;
            if (order.status != OrderStatus.Active && order.status != OrderStatus.PartiallyFilled) {
                continue;
            }
            if (order.trader != msg.sender) continue;

            uint256 remainingAmount = order.originalAmount - order.filledAmount;

            if (order.side == Side.Buy) {
                _bidCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
                if (_bidCohorts.getAvailableLiquidity(order.price) == 0) {
                    _bidTree.remove(order.price);
                }
            } else {
                _askCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
                if (_askCohorts.getAvailableLiquidity(order.price) == 0) {
                    _askTree.remove(order.price);
                }
            }

            order.status = OrderStatus.Cancelled;
            cancelledCount++;

            emit OrderCancelled(orderId, msg.sender, remainingAmount);
        }

        // Update best prices
        _updateBestBid();
        _updateBestAsk();
    }

    // ============ Admin Functions ============

    /**
     * @dev Advance the generation counter.
     *      This creates a new generation for subsequent orders.
     */
    function advanceGeneration() external override {
        _advanceGeneration();
    }

    /**
     * @dev Emergency cancel an order (only owner).
     */
    function emergencyCancel(uint96 orderId) external override onlyOwner {
        Order storage order = _orders[orderId];
        if (order.status == OrderStatus.None) revert OrderNotFound();

        uint256 remainingAmount = order.originalAmount - order.filledAmount;

        if (order.side == Side.Buy) {
            _bidCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
            if (_bidCohorts.getAvailableLiquidity(order.price) == 0) {
                _bidTree.remove(order.price);
            }
        } else {
            _askCohorts.removeLiquidity(order.price, remainingAmount, order.generation);
            if (_askCohorts.getAvailableLiquidity(order.price) == 0) {
                _askTree.remove(order.price);
            }
        }

        order.status = OrderStatus.Cancelled;

        // Update best prices
        _updateBestBid();
        _updateBestAsk();

        emit OrderCancelled(orderId, order.trader, remainingAmount);
    }

    // ============ Internal Functions ============

    /**
     * @dev Execute a buy order against asks.
     */
    function _executeAgainstAsks(uint256 amount, uint96 orderId, address trader)
        internal
        returns (FillResult memory result)
    {
        result.remainingAmount = amount;
        result.filledAmount = 0;

        uint256[] memory fillAmounts = new uint256[](100);
        uint256[] memory fillPrices = new uint256[](100);
        uint256 fillCount = 0;

        while (result.remainingAmount > 0 && _bestAsk != 0) {
            uint96 askPrice = _bestAsk;
            uint256 available = _askCohorts.getAvailableLiquidity(askPrice);

            if (available == 0) {
                _askTree.remove(askPrice);
                _updateBestAsk();
                continue;
            }

            uint256 fillAmount = result.remainingAmount > available ? available : result.remainingAmount;

            // Fill from cohorts at this price level
            _fillFromPriceLevel(_askCohorts, askPrice, fillAmount);

            // Calculate quote amount
            uint256 quoteAmount = OrderBookMath.calculateQuoteAmount(askPrice, fillAmount);

            // Record fill
            if (fillCount < 100) {
                fillAmounts[fillCount] = fillAmount;
                fillPrices[fillCount] = askPrice;
                fillCount++;
            }

            unchecked {
                result.filledAmount += fillAmount;
                result.remainingAmount -= fillAmount;
                result.totalQuoteAmount += quoteAmount;
            }

            // Check if price level is exhausted
            if (_askCohorts.getAvailableLiquidity(askPrice) == 0) {
                _askTree.remove(askPrice);
                _updateBestAsk();
            }

            emit TradeExecuted(orderId, trader, address(0), askPrice, fillAmount, Side.Buy);
        }

        // Calculate average price
        if (fillCount > 0) {
            uint256 totalWeighted;
            uint256 totalAmount;
            for (uint256 i = 0; i < fillCount; i++) {
                totalWeighted += fillAmounts[i] * fillPrices[i];
                totalAmount += fillAmounts[i];
            }
            result.avgPrice = totalAmount > 0 ? totalWeighted / totalAmount : 0;
        }

        return result;
    }

    /**
     * @dev Execute a sell order against bids.
     */
    function _executeAgainstBids(uint256 amount, uint96 orderId, address trader)
        internal
        returns (FillResult memory result)
    {
        result.remainingAmount = amount;
        result.filledAmount = 0;

        uint256[] memory fillAmounts = new uint256[](100);
        uint256[] memory fillPrices = new uint256[](100);
        uint256 fillCount = 0;

        while (result.remainingAmount > 0 && _bestBid != 0) {
            uint96 bidPrice = _bestBid;
            uint256 available = _bidCohorts.getAvailableLiquidity(bidPrice);

            if (available == 0) {
                _bidTree.remove(bidPrice);
                _updateBestBid();
                continue;
            }

            uint256 fillAmount = result.remainingAmount > available ? available : result.remainingAmount;

            // Fill from cohorts at this price level
            _fillFromPriceLevel(_bidCohorts, bidPrice, fillAmount);

            // Calculate quote amount
            uint256 quoteAmount = OrderBookMath.calculateQuoteAmount(bidPrice, fillAmount);

            // Record fill
            if (fillCount < 100) {
                fillAmounts[fillCount] = fillAmount;
                fillPrices[fillCount] = bidPrice;
                fillCount++;
            }

            unchecked {
                result.filledAmount += fillAmount;
                result.remainingAmount -= fillAmount;
                result.totalQuoteAmount += quoteAmount;
            }

            // Check if price level is exhausted
            if (_bidCohorts.getAvailableLiquidity(bidPrice) == 0) {
                _bidTree.remove(bidPrice);
                _updateBestBid();
            }

            emit TradeExecuted(orderId, trader, address(0), bidPrice, fillAmount, Side.Sell);
        }

        // Calculate average price
        if (fillCount > 0) {
            uint256 totalWeighted;
            uint256 totalAmount;
            for (uint256 i = 0; i < fillCount; i++) {
                totalWeighted += fillAmounts[i] * fillPrices[i];
                totalAmount += fillAmounts[i];
            }
            result.avgPrice = totalAmount > 0 ? totalWeighted / totalAmount : 0;
        }

        return result;
    }

    /**
     * @dev Fill from all cohorts at a price level.
     */
    function _fillFromPriceLevel(
        CohortManager.CohortStore storage store,
        uint96 price,
        uint256 amount
    ) internal returns (uint256 filledAmount) {
        uint64[] memory generations = store.getActiveGenerations(price);
        uint256 remaining = amount;

        for (uint256 i = 0; i < generations.length && remaining > 0; i++) {
            uint64 generation = generations[i];
            ICohortOrderBook.Cohort memory cohort = store.getCohort(price, generation);

            if (cohort.exists && cohort.totalAmount > cohort.filledAmount) {
                uint256 available = cohort.totalAmount - cohort.filledAmount;
                uint256 fillAmount = remaining > available ? available : remaining;

                store.fillLiquidity(price, fillAmount, generation);

                unchecked {
                    remaining -= fillAmount;
                    filledAmount += fillAmount;
                }
            }
        }
    }

    /**
     * @dev Update best prices after adding liquidity.
     */
    function _updateBestPrices(Side side, uint96 price) internal {
        if (side == Side.Buy) {
            if (_bestBid == 0 || price > _bestBid) {
                _bestBid = price;
            }
        } else {
            if (_bestAsk == 0 || price < _bestAsk) {
                _bestAsk = price;
            }
        }
    }

    /**
     * @dev Update best bid after removal.
     */
    function _updateBestBid() internal {
        (uint96 price, bool exists) = _bidTree.getBest();
        _bestBid = exists ? price : 0;
    }

    /**
     * @dev Update best ask after removal.
     */
    function _updateBestAsk() internal {
        (uint96 price, bool exists) = _askTree.getBest();
        _bestAsk = exists ? price : 0;
    }

    /**
     * @dev Auto-advance generation if new block.
     */
    function _autoAdvanceGeneration() internal {
        if (block.number > _lastGenerationBlock) {
            _advanceGeneration();
        }
    }

    /**
     * @dev Advance the generation counter.
     */
    function _advanceGeneration() internal {
        unchecked {
            _currentGeneration++;
        }
        _lastGenerationBlock = uint48(block.number);
        emit GenerationAdvanced(_currentGeneration, uint48(block.number));
    }
}
