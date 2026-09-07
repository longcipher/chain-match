// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICohortOrderBook} from "../interfaces/ICohortOrderBook.sol";

/**
 * @title CohortManager
 * @dev Manages cohorts (generational liquidity groups) at each price level.
 *
 * The key insight of generational fungible liquidity:
 * - Orders placed at the same price level within the same generation are fungible
 * - They share fills proportionally based on their contribution to the cohort
 * - This enables O(1) operations since we only track cohort totals, not individual orders
 */
library CohortManager {
    using CohortManager for CohortManager.CohortStore;

    struct Cohort {
        uint256 totalAmount;
        uint256 filledAmount;
        uint256 orderCount;
        uint64 generation;
        bool exists;
    }

    struct CohortStore {
        // price => generation => cohort
        mapping(uint96 => mapping(uint64 => Cohort)) cohorts;
        // price => active generation IDs
        mapping(uint96 => uint64[]) activeGenerations;
        // price => generation index in activeGenerations array
        mapping(uint96 => mapping(uint64 => uint256)) generationIndex;
        // price => total liquidity
        mapping(uint96 => uint256) totalLiquidity;
        // price => filled liquidity
        mapping(uint96 => uint256) filledLiquidity;
        // price => cohort count
        mapping(uint96 => uint256) cohortCount;
        // price => exists
        mapping(uint96 => bool) levelExists;
    }

    /**
     * @dev Add liquidity to a cohort at a specific price level.
     *      If the cohort for the current generation doesn't exist, create it.
     */
    function addLiquidity(
        CohortStore storage self,
        uint96 price,
        uint256 amount,
        uint64 generation
    ) internal returns (bool newCohort) {
        Cohort storage cohort = self.cohorts[price][generation];

        if (!cohort.exists) {
            // Create new cohort
            self.cohorts[price][generation] = Cohort({
                totalAmount: amount,
                filledAmount: 0,
                orderCount: 1,
                generation: generation,
                exists: true
            });

            // Add to active generations
            self.generationIndex[price][generation] = self.activeGenerations[price].length;
            self.activeGenerations[price].push(generation);

            // Update price level stats
            if (!self.levelExists[price]) {
                self.levelExists[price] = true;
            }
            self.cohortCount[price]++;

            newCohort = true;
        } else {
            // Add to existing cohort
            unchecked {
                cohort.totalAmount += amount;
                cohort.orderCount++;
            }
            newCohort = false;
        }

        // Update total liquidity
        unchecked {
            self.totalLiquidity[price] += amount;
        }
    }

    /**
     * @dev Remove liquidity from a cohort (for cancellations).
     */
    function removeLiquidity(
        CohortStore storage self,
        uint96 price,
        uint256 amount,
        uint64 generation
    ) internal returns (bool cohortEmpty) {
        Cohort storage cohort = self.cohorts[price][generation];
        require(cohort.exists, "Cohort not found");

        unchecked {
            // Update cohort
            cohort.totalAmount -= amount;
            cohort.orderCount--;

            // Update price level
            self.totalLiquidity[price] -= amount;

            // Check if cohort is empty
            if (cohort.totalAmount == 0 || cohort.totalAmount <= cohort.filledAmount) {
                cohortEmpty = true;
                _removeCohort(self, price, generation);
            } else {
                cohortEmpty = false;
            }
        }
    }

    /**
     * @dev Fill liquidity from a cohort.
     * @return filledAmount The actual amount filled
     */
    function fillLiquidity(
        CohortStore storage self,
        uint96 price,
        uint256 amount,
        uint64 generation
    ) internal returns (uint256 filledAmount) {
        Cohort storage cohort = self.cohorts[price][generation];
        require(cohort.exists, "Cohort not found");

        uint256 available = cohort.totalAmount - cohort.filledAmount;

        unchecked {
            filledAmount = amount > available ? available : amount;
            cohort.filledAmount += filledAmount;
            self.filledLiquidity[price] += filledAmount;

            // If cohort is fully filled, remove it
            if (cohort.filledAmount >= cohort.totalAmount) {
                _removeCohort(self, price, generation);
            }
        }
    }

    /**
     * @dev Get the available (unfilled) liquidity at a price level.
     */
    function getAvailableLiquidity(CohortStore storage self, uint96 price)
        internal
        view
        returns (uint256 available)
    {
        uint256 total = self.totalLiquidity[price];
        uint256 filled = self.filledLiquidity[price];
        unchecked {
            available = total > filled ? total - filled : 0;
        }
    }

    /**
     * @dev Get the fill ratio for a specific cohort.
     */
    function getFillRatio(CohortStore storage self, uint96 price, uint64 generation)
        internal
        view
        returns (uint256 numerator, uint256 denominator)
    {
        Cohort storage cohort = self.cohorts[price][generation];
        if (!cohort.exists) {
            return (0, 0);
        }
        return (cohort.filledAmount, cohort.totalAmount);
    }

    /**
     * @dev Get active generations for a price level.
     */
    function getActiveGenerations(CohortStore storage self, uint96 price)
        internal
        view
        returns (uint64[] memory)
    {
        return self.activeGenerations[price];
    }

    /**
     * @dev Check if a price level exists.
     */
    function hasPriceLevel(CohortStore storage self, uint96 price) internal view returns (bool) {
        return self.levelExists[price];
    }

    /**
     * @dev Get cohort details.
     */
    function getCohort(CohortStore storage self, uint96 price, uint64 generation)
        internal
        view
        returns (ICohortOrderBook.Cohort memory)
    {
        Cohort storage c = self.cohorts[price][generation];
        return ICohortOrderBook.Cohort({
            totalAmount: c.totalAmount,
            filledAmount: c.filledAmount,
            orderCount: c.orderCount,
            generation: c.generation,
            exists: c.exists
        });
    }

    /**
     * @dev Get price level details.
     */
    function getPriceLevel(CohortStore storage self, uint96 price)
        internal
        view
        returns (ICohortOrderBook.PriceLevel memory)
    {
        return ICohortOrderBook.PriceLevel({
            totalLiquidity: self.totalLiquidity[price],
            filledLiquidity: self.filledLiquidity[price],
            cohortCount: self.cohortCount[price],
            exists: self.levelExists[price]
        });
    }

    /**
     * @dev Internal function to remove a cohort.
     */
    function _removeCohort(CohortStore storage self, uint96 price, uint64 generation) internal {
        // Remove from active generations array (swap and pop)
        uint256 index = self.generationIndex[price][generation];
        uint256 lastIndex = self.activeGenerations[price].length - 1;

        if (index != lastIndex) {
            uint64 lastGeneration = self.activeGenerations[price][lastIndex];
            self.activeGenerations[price][index] = lastGeneration;
            self.generationIndex[price][lastGeneration] = index;
        }

        self.activeGenerations[price].pop();
        delete self.generationIndex[price][generation];
        delete self.cohorts[price][generation];

        // Update cohort count
        unchecked {
            self.cohortCount[price]--;
        }

        // If no more cohorts, remove price level
        if (self.cohortCount[price] == 0) {
            self.levelExists[price] = false;
            self.totalLiquidity[price] = 0;
            self.filledLiquidity[price] = 0;
        }
    }
}
