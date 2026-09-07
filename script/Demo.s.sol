// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CohortOrderBook} from "../src/CohortOrderBook.sol";
import {ICohortOrderBook} from "../src/interfaces/ICohortOrderBook.sol";

contract DemoScript is Script {
    // Anvil test accounts
    address public deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public alice = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address public bob = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    function run() external {
        // Load deployed contract address
        CohortOrderBook orderBook = CohortOrderBook(payable(0x5FbDB2315678afecb367f032d93F642f64180aa3));

        console.log("=== Cohort Order Book Demo ===");
        console.log("Contract address:", address(orderBook));

        // Scenario 1: Market maker places limit orders
        console.log("\n--- Scenario 1: Market Making ---");
        vm.startBroadcast(deployer);

        // Place buy orders
        uint96 buyOrderId1 = orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, 1000 ether, 10 ether);
        console.log("Placed buy order ID:", buyOrderId1, "at price 1000, amount 10");

        uint96 buyOrderId2 = orderBook.placeLimitOrder(ICohortOrderBook.Side.Buy, 990 ether, 20 ether);
        console.log("Placed buy order ID:", buyOrderId2, "at price 990, amount 20");

        // Place sell orders
        uint96 sellOrderId1 = orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, 1010 ether, 10 ether);
        console.log("Placed sell order ID:", sellOrderId1, "at price 1010, amount 10");

        uint96 sellOrderId2 = orderBook.placeLimitOrder(ICohortOrderBook.Side.Sell, 1020 ether, 20 ether);
        console.log("Placed sell order ID:", sellOrderId2, "at price 1020, amount 20");

        vm.stopBroadcast();

        // Check order book state
        (uint96 bestBid, uint256 bidLiquidity) = orderBook.getBestBid();
        (uint96 bestAsk, uint256 askLiquidity) = orderBook.getBestAsk();

        console.log("\nOrder Book State:");
        console.log("Best Bid:", bestBid, "Liquidity:", bidLiquidity);
        console.log("Best Ask:", bestAsk, "Liquidity:", askLiquidity);
        console.log("Spread:", orderBook.getSpread());

        // Scenario 2: Trader places market order
        console.log("\n--- Scenario 2: Market Order ---");
        vm.startBroadcast(alice);

        ICohortOrderBook.FillResult memory result =
            orderBook.placeMarketOrder(ICohortOrderBook.Side.Buy, 5 ether);

        console.log("Alice bought 5 ether:");
        console.log("  Filled:", result.filledAmount);
        console.log("  Avg Price:", result.avgPrice);
        console.log("  Remaining:", result.remainingAmount);

        vm.stopBroadcast();

        // Check updated state
        (bestAsk, askLiquidity) = orderBook.getBestAsk();
        console.log("\nUpdated Best Ask:", bestAsk, "Liquidity:", askLiquidity);

        // Scenario 3: Cancel order
        console.log("\n--- Scenario 3: Cancel Order ---");
        vm.startBroadcast(deployer);

        orderBook.cancelOrder(buyOrderId1);
        console.log("Cancelled buy order ID:", buyOrderId1);

        vm.stopBroadcast();

        // Check final state
        (bestBid, bidLiquidity) = orderBook.getBestBid();
        (bestAsk, askLiquidity) = orderBook.getBestAsk();

        console.log("\nFinal Order Book State:");
        console.log("Best Bid:", bestBid, "Liquidity:", bidLiquidity);
        console.log("Best Ask:", bestAsk, "Liquidity:", askLiquidity);
        console.log("Current Generation:", orderBook.getCurrentGeneration());

        console.log("\n=== Demo Complete ===");
    }
}
