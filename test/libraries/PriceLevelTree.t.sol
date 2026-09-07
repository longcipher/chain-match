// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PriceLevelTree} from "../../src/libraries/PriceLevelTree.sol";

/**
 * @title PriceLevelTreeWrapper
 * @dev Wrapper contract to expose PriceLevelTree functions for testing.
 */
contract PriceLevelTreeWrapper {
    using PriceLevelTree for PriceLevelTree.Tree;

    PriceLevelTree.Tree private tree;

    constructor() {
        tree.initialize();
    }

    function insert(uint96 price) external {
        tree.insert(price, true);
    }

    function remove(uint96 price) external {
        tree.remove(price);
    }

    function getBest() external view returns (uint96 price, bool exists) {
        return tree.getBest();
    }

    function getWorst() external view returns (uint96 price, bool exists) {
        return tree.getWorst();
    }

    function getNext(uint96 price, bool isBid) external view returns (uint96) {
        return tree.getNext(price, isBid);
    }

    function getPrev(uint96 price, bool isBid) external view returns (uint96) {
        return tree.getPrev(price, isBid);
    }

    function contains(uint96 price) external view returns (bool) {
        return tree.contains(price);
    }

    function getCount() external view returns (uint256) {
        return tree.nodeCount;
    }

    function getPrices(uint256 maxLevels, bool isBid) external view returns (uint96[] memory) {
        return tree.getPrices(maxLevels, isBid);
    }
}

/**
 * @title PriceLevelTreeTest
 * @dev Tests for the PriceLevelTree library via wrapper contract.
 */
contract PriceLevelTreeTest is Test {
    PriceLevelTreeWrapper public wrapper;

    function setUp() public {
        wrapper = new PriceLevelTreeWrapper();
    }

    function test_Insert_FirstNode() public {
        wrapper.insert(100); // Bid
        assertEq(wrapper.getCount(), 1);
        assertTrue(wrapper.contains(100));

        (uint96 best, bool exists) = wrapper.getBest();
        assertEq(best, 100);
        assertTrue(exists);
    }

    function test_Insert_Bid_Descending() public {
        // Bids should be sorted descending (highest first)
        wrapper.insert(100);
        wrapper.insert(200);
        wrapper.insert(150);

        assertEq(wrapper.getCount(), 3);

        (uint96 best, ) = wrapper.getBest();
        assertEq(best, 200); // Highest bid is best

        (uint96 worst, ) = wrapper.getWorst();
        assertEq(worst, 100); // Lowest bid is worst
    }

    function test_Insert_Duplicate() public {
        wrapper.insert(100);
        vm.expectRevert("Price exists");
        wrapper.insert(100);
    }

    function test_Insert_ZeroPrice() public {
        vm.expectRevert("Invalid price");
        wrapper.insert(0);
    }

    function test_Remove_Head() public {
        wrapper.insert(200);
        wrapper.insert(150);
        wrapper.insert(100);

        wrapper.remove(200);

        assertEq(wrapper.getCount(), 2);
        assertFalse(wrapper.contains(200));

        (uint96 best, ) = wrapper.getBest();
        assertEq(best, 150);
    }

    function test_Remove_Tail() public {
        wrapper.insert(200);
        wrapper.insert(150);
        wrapper.insert(100);

        wrapper.remove(100);

        assertEq(wrapper.getCount(), 2);
        assertFalse(wrapper.contains(100));

        (uint96 worst, ) = wrapper.getWorst();
        assertEq(worst, 150);
    }

    function test_Remove_Middle() public {
        wrapper.insert(200);
        wrapper.insert(150);
        wrapper.insert(100);

        wrapper.remove(150);

        assertEq(wrapper.getCount(), 2);
        assertFalse(wrapper.contains(150));

        (uint96 best, ) = wrapper.getBest();
        assertEq(best, 200);

        (uint96 worst, ) = wrapper.getWorst();
        assertEq(worst, 100);
    }

    function test_Remove_LastNode() public {
        wrapper.insert(100);
        wrapper.remove(100);

        assertEq(wrapper.getCount(), 0);
        assertFalse(wrapper.contains(100));

        (, bool exists) = wrapper.getBest();
        assertFalse(exists);
    }

    function test_Remove_NotFound() public {
        vm.expectRevert("Price not found");
        wrapper.remove(100);
    }

    function test_GetNext() public {
        wrapper.insert(200);
        wrapper.insert(150);
        wrapper.insert(100);

        uint96 next = wrapper.getNext(200, true);
        assertEq(next, 150);

        next = wrapper.getNext(150, true);
        assertEq(next, 100);

        next = wrapper.getNext(100, true);
        assertEq(next, 0); // No next
    }

    function test_GetPrev() public {
        wrapper.insert(200);
        wrapper.insert(150);
        wrapper.insert(100);

        uint96 prev = wrapper.getPrev(100, true);
        assertEq(prev, 150);

        prev = wrapper.getPrev(150, true);
        assertEq(prev, 200);

        prev = wrapper.getPrev(200, true);
        assertEq(prev, 0); // No prev
    }

    function test_Contains() public {
        wrapper.insert(100);
        assertTrue(wrapper.contains(100));
        assertFalse(wrapper.contains(200));
    }

    function test_Count() public {
        assertEq(wrapper.getCount(), 0);

        wrapper.insert(100);
        assertEq(wrapper.getCount(), 1);

        wrapper.insert(200);
        assertEq(wrapper.getCount(), 2);

        wrapper.remove(100);
        assertEq(wrapper.getCount(), 1);
    }

    function test_GetPrices() public {
        wrapper.insert(200);
        wrapper.insert(150);
        wrapper.insert(100);

        uint96[] memory prices = wrapper.getPrices(2, true);
        assertEq(prices.length, 2);
        assertEq(prices[0], 200);
        assertEq(prices[1], 150);
    }

    function test_GetPrices_MoreThanAvailable() public {
        wrapper.insert(200);
        wrapper.insert(150);

        uint96[] memory prices = wrapper.getPrices(5, true);
        assertEq(prices.length, 2);
    }

    function test_GetBest_Empty() public {
        (, bool exists) = wrapper.getBest();
        assertFalse(exists);
    }

    function test_GetWorst_Empty() public {
        (, bool exists) = wrapper.getWorst();
        assertFalse(exists);
    }

    function test_Insert_ManyNodes() public {
        // Insert many nodes to test tree structure
        for (uint96 i = 1; i <= 10; i++) {
            wrapper.insert(i * 10);
        }

        assertEq(wrapper.getCount(), 10);

        (uint96 best, ) = wrapper.getBest();
        assertEq(best, 100);

        (uint96 worst, ) = wrapper.getWorst();
        assertEq(worst, 10);
    }

    function test_Remove_AllNodes() public {
        wrapper.insert(100);
        wrapper.insert(200);
        wrapper.insert(300);

        wrapper.remove(200);
        wrapper.remove(100);
        wrapper.remove(300);

        assertEq(wrapper.getCount(), 0);
    }

    function test_DescendingOrder() public {
        // Verify bids are in descending order
        wrapper.insert(100);
        wrapper.insert(300);
        wrapper.insert(200);

        uint96[] memory prices = wrapper.getPrices(3, true);
        assertEq(prices[0], 300);
        assertEq(prices[1], 200);
        assertEq(prices[2], 100);
    }
}
