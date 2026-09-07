// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PriceLevelTree
 * @dev A sorted doubly-linked list for price levels that enables O(1) access to best bid/ask
 *      and O(1) insertion/deletion at known positions.
 *
 * This is a gas-efficient alternative to a full binary search tree for the common case
 * where we need fast access to the best prices and sequential iteration.
 */
library PriceLevelTree {
    struct Node {
        uint96 price;
        uint96 prevPrice;
        uint96 nextPrice;
        bool exists;
    }

    struct Tree {
        mapping(uint96 => Node) nodes;
        uint96 head; // Best bid (highest) for bids, Best ask (lowest) for asks
        uint96 tail; // Worst bid (lowest) for bids, Worst ask (highest) for asks
        uint256 nodeCount;
        bool initialized;
    }

    /**
     * @dev Initialize the tree.
     */
    function initialize(Tree storage self) internal {
        require(!self.initialized, "Already initialized");
        self.initialized = true;
        self.head = 0;
        self.tail = 0;
        self.nodeCount = 0;
    }

    /**
     * @dev Insert a price level into the sorted tree.
     * @param self The tree storage
     * @param price The price to insert
     * @param isBid Whether this is a bid (sorted descending) or ask (sorted ascending)
     */
    function insert(Tree storage self, uint96 price, bool isBid) internal {
        require(!self.nodes[price].exists, "Price exists");
        require(price > 0, "Invalid price");

        self.nodes[price] = Node({
            price: price,
            prevPrice: 0,
            nextPrice: 0,
            exists: true
        });

        if (self.nodeCount == 0) {
            // First node
            self.head = price;
            self.tail = price;
        } else if (isBid) {
            // Bids: sorted descending (highest first)
            if (price > self.head) {
                // New best bid
                self.nodes[price].nextPrice = self.head;
                self.nodes[self.head].prevPrice = price;
                self.head = price;
            } else if (price < self.tail) {
                // New worst bid
                self.nodes[price].prevPrice = self.tail;
                self.nodes[self.tail].nextPrice = price;
                self.tail = price;
            } else {
                // Insert in the middle
                _insertBetween(self, price, isBid);
            }
        } else {
            // Asks: sorted ascending (lowest first)
            if (price < self.head) {
                // New best ask
                self.nodes[price].nextPrice = self.head;
                self.nodes[self.head].prevPrice = price;
                self.head = price;
            } else if (price > self.tail) {
                // New worst ask
                self.nodes[price].prevPrice = self.tail;
                self.nodes[self.tail].nextPrice = price;
                self.tail = price;
            } else {
                // Insert in the middle
                _insertBetween(self, price, isBid);
            }
        }

        unchecked {
            self.nodeCount++;
        }
    }

    /**
     * @dev Remove a price level from the tree.
     */
    function remove(Tree storage self, uint96 price) internal {
        require(self.nodes[price].exists, "Price not found");

        Node storage node = self.nodes[price];

        if (self.nodeCount == 1) {
            // Last node
            self.head = 0;
            self.tail = 0;
        } else if (price == self.head) {
            // Remove head
            self.head = node.nextPrice;
            self.nodes[self.head].prevPrice = 0;
        } else if (price == self.tail) {
            // Remove tail
            self.tail = node.prevPrice;
            self.nodes[self.tail].nextPrice = 0;
        } else {
            // Remove from middle
            self.nodes[node.prevPrice].nextPrice = node.nextPrice;
            self.nodes[node.nextPrice].prevPrice = node.prevPrice;
        }

        delete self.nodes[price];

        unchecked {
            self.nodeCount--;
        }
    }

    /**
     * @dev Get the best price (head of the list).
     */
    function getBest(Tree storage self) internal view returns (uint96 price, bool exists) {
        if (self.nodeCount == 0) {
            return (0, false);
        }
        return (self.head, true);
    }

    /**
     * @dev Get the worst price (tail of the list).
     */
    function getWorst(Tree storage self) internal view returns (uint96 price, bool exists) {
        if (self.nodeCount == 0) {
            return (0, false);
        }
        return (self.tail, true);
    }

    /**
     * @dev Get the next price in the sorted order.
     * @param self The tree storage
     * @param price The current price
     * @param isBid Whether this is a bid or ask
     * @return nextPrice The next price (0 if none)
     */
    function getNext(Tree storage self, uint96 price, bool isBid) internal view returns (uint96 nextPrice) {
        Node storage node = self.nodes[price];
        if (!node.exists) return 0;

        if (isBid) {
            // For bids, next is lower price
            return node.nextPrice;
        } else {
            // For asks, next is higher price
            return node.nextPrice;
        }
    }

    /**
     * @dev Get the previous price in the sorted order.
     */
    function getPrev(Tree storage self, uint96 price, bool isBid) internal view returns (uint96 prevPrice) {
        Node storage node = self.nodes[price];
        if (!node.exists) return 0;

        if (isBid) {
            // For bids, prev is higher price
            return node.prevPrice;
        } else {
            // For asks, prev is lower price
            return node.prevPrice;
        }
    }

    /**
     * @dev Check if a price exists in the tree.
     */
    function contains(Tree storage self, uint96 price) internal view returns (bool) {
        return self.nodes[price].exists;
    }

    /**
     * @dev Get the count of price levels.
     */
    function count(Tree storage self) internal view returns (uint256) {
        return self.nodeCount;
    }

    /**
     * @dev Iterate through prices starting from best.
     * @param self The tree storage
     * @param maxLevels Maximum number of levels to return
     * @param isBid Whether this is a bid or ask
     * @return prices Array of prices
     */
    function getPrices(Tree storage self, uint256 maxLevels, bool isBid)
        internal
        view
        returns (uint96[] memory prices)
    {
        uint256 resultCount = maxLevels > self.nodeCount ? self.nodeCount : maxLevels;
        prices = new uint96[](resultCount);

        uint96 current = self.head;
        for (uint256 i = 0; i < resultCount && current != 0; i++) {
            prices[i] = current;
            current = self.nodes[current].nextPrice;
        }
    }

    /**
     * @dev Internal function to insert a price in the middle of the sorted list.
     */
    function _insertBetween(Tree storage self, uint96 price, bool isBid) internal {
        if (isBid) {
            // Bids: sorted descending
            // Find the first node with price less than the new price
            uint96 current = self.head;
            while (current != 0 && current > price) {
                current = self.nodes[current].nextPrice;
            }

            if (current == 0) {
                // Insert at tail
                self.nodes[price].prevPrice = self.tail;
                self.nodes[self.tail].nextPrice = price;
                self.tail = price;
            } else {
                // Insert before current
                uint96 prevPrice = self.nodes[current].prevPrice;
                self.nodes[price].prevPrice = prevPrice;
                self.nodes[price].nextPrice = current;
                self.nodes[current].prevPrice = price;
                if (prevPrice != 0) {
                    self.nodes[prevPrice].nextPrice = price;
                }
            }
        } else {
            // Asks: sorted ascending
            // Find the first node with price greater than the new price
            uint96 current = self.head;
            while (current != 0 && current < price) {
                current = self.nodes[current].nextPrice;
            }

            if (current == 0) {
                // Insert at tail
                self.nodes[price].prevPrice = self.tail;
                self.nodes[self.tail].nextPrice = price;
                self.tail = price;
            } else {
                // Insert before current
                uint96 prevPrice = self.nodes[current].prevPrice;
                self.nodes[price].prevPrice = prevPrice;
                self.nodes[price].nextPrice = current;
                self.nodes[current].prevPrice = price;
                if (prevPrice != 0) {
                    self.nodes[prevPrice].nextPrice = price;
                }
            }
        }
    }
}
