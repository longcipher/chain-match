// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CohortOrderBook} from "../src/CohortOrderBook.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        vm.startBroadcast(deployerPrivateKey);
        CohortOrderBook orderBook = new CohortOrderBook();
        vm.stopBroadcast();
        console.log("CohortOrderBook deployed at:", address(orderBook));
    }
}
