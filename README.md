# Cohort Order Book

An O(1) fully on-chain limit order book via generational fungible liquidity.

## Overview

The Cohort Order Book is a fully decentralized, on-chain limit order book implementation that achieves O(1) time complexity for core operations (order placement, cancellation, and matching) through the novel concept of **generational fungible liquidity**.

### Key Innovation: Generational Fungible Liquidity

Instead of tracking individual orders, liquidity is grouped into "cohorts" at each price level. All orders placed at the same price level within the same generation are fungible—they share fills proportionally based on their contribution to the cohort.

This enables:
- **O(1) Order Placement** - Just update cohort totals
- **O(1) Order Cancellation** - Just update cohort totals
- **O(1) Matching** - Fill entire cohorts at once

The generation counter advances periodically (e.g., per block), creating new cohorts. This ensures that older liquidity gets filled first (time priority) while maintaining O(1) operations.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      CohortOrderBook                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  PriceLevelTree │  │  CohortManager  │  │  OrderBookMath  │  │
│  │  (Sorted List)  │  │  (Cohort Store) │  │  (Calculations) │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    ICohortOrderBook                         ││
│  │              (Interface & Events)                          ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### Core Components

| Component | Purpose | Complexity |
|-----------|---------|------------|
| `PriceLevelTree` | Sorted doubly-linked list for price levels | O(1) best bid/ask |
| `CohortManager` | Manages cohorts at each price level | O(1) add/remove/fill |
| `OrderBookMath` | Mathematical utilities | O(1) calculations |
| `CohortOrderBook` | Main contract with all operations | O(1) for core ops |

## Project Structure

```
cohort-order-book/
├── src/
│   ├── CohohortOrderBook.sol          # Main contract
│   ├── interfaces/
│   │   └── ICohortOrderBook.sol       # Interface & types
│   └── libraries/
│       ├── CohortManager.sol          # Cohort management
│       ├── OrderBookMath.sol          # Math utilities
│       └── PriceLevelTree.sol         # Price level tree
├── test/
│   ├── CohortOrderBook.t.sol          # Unit tests (51 tests)
│   ├── CohortOrderBook.e2e.t.sol      # E2E tests (16 tests)
│   └── libraries/
│       ├── OrderBookMath.t.sol        # Math library tests
│       └── PriceLevelTree.t.sol       # Tree library tests
├── script/
│   ├── Deploy.s.sol                   # Deployment script
│   └── Demo.s.sol                     # Demo script
├── foundry.toml                       # Foundry configuration
└── soldeer.config.json                # Soldeer package config
```

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, anvil, cast)
- [Soldeer](https://github.com/mario-eth/soldeer) (optional, for package management)

### Installation

```bash
# Clone the repository
git clone https://github.com/longcipher/chain-match.git
cd chain-match/cohort-order-book

# Install dependencies (if soldeer registry is available)
soldeer update

# Or manually install dependencies to dependencies/ directory
```

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vvv

# Run specific test file
forge test --match-path test/CohortOrderBook.t.sol

# Run with gas reporting
forge test --gas-report

# Run with coverage
forge coverage
```

### Deploy

```bash
# Deploy to local Anvil
anvil &
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to testnet/mainnet
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast --verify
```

## Usage

### Placing a Limit Order

```solidity
// Place a buy limit order: buy 10 ETH at 1000 USDC
uint96 orderId = orderBook.placeLimitOrder(
    ICohortOrderBook.Side.Buy,  // side
    1000 ether,                  // price (1e18 precision)
    10 ether                     // amount (1e18 precision)
);
```

### Placing a Market Order

```solidity
// Buy 5 ETH at market price
ICohortOrderBook.FillResult memory result = orderBook.placeMarketOrder(
    ICohortOrderBook.Side.Buy,
    5 ether
);

// Check fill results
uint256 filled = result.filledAmount;
uint256 avgPrice = result.avgPrice;
uint256 remaining = result.remainingAmount;
```

### Cancelling Orders

```solidity
// Cancel a single order
orderBook.cancelOrder(orderId);

// Cancel all orders for a trader
uint256 cancelled = orderBook.cancelAllOrders(trader);

// Cancel orders by side
uint256 cancelled = orderBook.cancelOrdersByPrice(trader, ICohortOrderBook.Side.Buy);

// Cancel orders at specific price
uint256 cancelled = orderBook.cancelOrdersByPrice(trader, 1000 ether, ICohortOrderBook.Side.Buy);
```

### Batch Operations

```solidity
// Place multiple orders in one transaction
ICohortOrderBook.Side[] memory sides = new ICohortOrderBook.Side[](2);
uint96[] memory prices = new uint96[](2);
uint256[] memory amounts = new uint256[](2);

sides[0] = ICohortOrderBook.Side.Buy;
sides[1] = ICohortOrderBook.Side.Sell;
prices[0] = 1000 ether;
prices[1] = 1010 ether;
amounts[0] = 10 ether;
amounts[1] = 10 ether;

uint96[] memory orderIds = orderBook.batchPlaceLimitOrders(sides, prices, amounts);

// Cancel multiple orders
uint256 cancelled = orderBook.batchCancelOrders(orderIds);
```

### Reading Order Book State

```solidity
// Get best bid/ask
(uint96 bestBid, uint256 bidLiquidity) = orderBook.getBestBid();
(uint96 bestAsk, uint256 askLiquidity) = orderBook.getBestAsk();

// Get spread and mid price
uint256 spread = orderBook.getSpread();
uint256 midPrice = orderBook.getMidPrice();

// Get order book depth
(uint96[] memory prices, uint256[] memory liquidity) =
    orderBook.getOrderBookDepth(ICohortOrderBook.Side.Buy, 10);

// Get specific order
ICohortOrderBook.Order memory order = orderBook.getOrder(orderId);

// Get price level details
ICohortOrderBook.PriceLevel memory level = orderBook.getPriceLevel(1000 ether, ICohortOrderBook.Side.Buy);

// Get cohort details
ICohortOrderBook.Cohort memory cohort = orderBook.getCohort(
    1000 ether,
    ICohortOrderBook.Side.Buy,
    1 // generation
);

// Get current generation
uint64 currentGen = orderBook.getCurrentGeneration();

// Get overall state
ICohortOrderBook.OrderBookState memory state = orderBook.getOrderBookState();
```

## API Reference

### Enums

```solidity
enum OrderType { Limit, Market }
enum Side { Buy, Sell }
enum OrderStatus { None, Active, PartiallyFilled, Filled, Cancelled }
```

### Structs

```solidity
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

struct FillResult {
    uint256 filledAmount;
    uint256 remainingAmount;
    uint256 avgPrice;
    uint256 totalQuoteAmount;
    Trade[] trades;
}

struct PriceLevel {
    uint256 totalLiquidity;
    uint256 filledLiquidity;
    uint256 cohortCount;
    bool exists;
}

struct Cohort {
    uint256 totalAmount;
    uint256 filledAmount;
    uint256 orderCount;
    uint64 generation;
    bool exists;
}
```

### Events

```solidity event OrderPlaced(uint96 indexed orderId, address indexed trader, Side side, uint96 price, uint256 amount, uint64 generation);
event OrderCancelled(uint96 indexed orderId, address indexed trader, uint256 remainingAmount);
event OrderFilled(uint96 indexed orderId, address indexed trader, uint96 price, uint256 amount, uint64 generation);
event CohortUpdated(uint96 indexed price, Side side, uint64 indexed generation, uint256 totalAmount, uint256 filledAmount);
event TradeExecuted(uint96 indexed orderId, address indexed trader, address indexed counterparty, uint96 price, uint256 amount, Side side);
event GenerationAdvanced(uint64 indexed newGeneration, uint48 blockNumber);
event PriceLevelAdded(uint96 indexed price, Side side);
```

### Errors

```solidity
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
```

## Test Results

### Coverage Report

| File | Lines | Statements | Branches | Functions |
|------|-------|------------|----------|-----------|
| CohortOrderBook.sol | 90.83% | 89.26% | 77.01% | 100.00% |
| CohortManager.sol | 95.31% | 96.67% | 84.62% | 90.00% |
| OrderBookMath.sol | 100.00% | 100.00% | 66.67% | 100.00% |
| PriceLevelTree.sol | 90.65% | 89.32% | 83.33% | 90.91% |

### Test Suites

| Suite | Tests | Status |
|-------|-------|--------|
| CohortOrderBookTest | 51 | ✅ All passing |
| CohortOrderBookE2ETest | 16 | ✅ All passing |
| OrderBookMathTest | 21 | ✅ All passing |
| PriceLevelTreeTest | 20 | ✅ All passing |
| **Total** | **108** | **✅ All passing** |

### Gas Benchmarks

| Operation | Gas Used |
|-----------|----------|
| Place Limit Order | ~480,000 |
| Place Market Order | ~720,000 |
| Cancel Order | ~550,000 |
| Batch Place (3 orders) | ~1,260,000 |
| Batch Cancel (2 orders) | ~1,040,000 |

## Design Decisions

### 1. Generational Fungible Liquidity

Orders at the same price level within the same generation are treated as fungible. This means:
- All orders in a cohort share fills proportionally
- Individual order tracking is maintained for trader reference
- Cohort-level operations are O(1)

### 2. Price Level Tree

A sorted doubly-linked list is used instead of a binary search tree because:
- O(1) access to best bid/ask (head of list)
- O(1) insertion at known positions
- Sequential iteration for order book depth
- Lower gas overhead than tree structures

### 3. Generation Advancement

Generations advance automatically per block:
- Ensures time priority (older orders filled first)
- Creates natural batching of orders
- Can be manually advanced via `advanceGeneration()`

### 4. Storage Optimization

- `uint96` for prices (sufficient precision)
- `uint64` for generations (enough for ~584 years at 1 block/generation)
- Packed structs to minimize storage reads
- Cached best prices for O(1) access

## Security Considerations

1. **Reentrancy Protection** - All state-changing functions use `nonReentrant` modifier
2. **Access Control** - Only order owners can cancel their orders
3. **Input Validation** - All inputs are validated with custom errors
4. **No Direct ETH** - Contract rejects direct ETH transfers
5. **Emergency Functions** - Owner can emergency cancel orders if needed

## Performance Characteristics

| Operation | Time Complexity | Gas (approx) |
|-----------|-----------------|--------------|
| Place Limit Order | O(1) | 480,000 |
| Place Market Order | O(n) where n = price levels filled | 720,000 |
| Cancel Order | O(1) | 550,000 |
| Get Best Bid/Ask | O(1) | 2,500 (view) |
| Get Order Book Depth | O(n) where n = levels requested | 10,000 * n |

## Future Enhancements

- [ ] Stop-loss orders
- [ ] Take-profit orders
- [ ] Iceberg orders (hidden size)
- [ ] Time-in-force options (IOC, FOK, GTC)
- [ ] Fee structure integration
- [ ] Oracle price feeds
- [ ] Cross-margin support
- [ ] Liquidity mining rewards

## References

- [Ethereum Magicians: Cohort Order Book](https://ethereum-magicians.org/t/cohort-order-book-an-o-1-fully-on-chain-limit-order-book-via-generational-fungible-liquidity/29018)
- [Fenwick + Bitmap: constant-time matching for on-chain order books](https://ethresear.ch/t/fenwick-bitmap-constant-time-matching-for-on-chain-order-books/22313)
- [On-Chain Limit Order Books - Monad](https://monadxyz.substack.com/p/on-chain-limit-order-books)

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Acknowledgments

- [Foundry](https://github.com/foundry-rs/foundry) - Ethereum development framework
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts) - Smart contract security
- [Soldeer](https://github.com/mario-eth/soldeer) - Solidity package manager
