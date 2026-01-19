// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { Config } from "forge-std/Config.sol";

import { GenericUnitL2 } from "lib/generic-protocol/src/unit/GenericUnitL2.sol";

import { BridgeCoordinatorL2 } from "../src/BridgeCoordinatorL2.sol";
import { LayerZeroAdapter } from "../src/adapters/LayerZeroAdapter.sol";
import { LineaBridgeAdapter } from "../src/adapters/LineaBridgeAdapter.sol";

contract Check is Script, Config {
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// forge script script/Check.s.sol:Check --sig "checkL2()" --via-ir --chain-id {chain id}
    /// @dev --via-ir is required if deployed contracts were compiled with --via-ir
    /// addresses must be filled in addrs/deployments.toml
    function checkL2() external {
        _loadConfig("./addrs/deployments.toml", false);

        vm.createSelectFork(config.getRpcUrl());

        address unitToken = config.get("generic_unit_l2").toAddress();
        require(unitToken != address(0), "generic_unit_l2 not set");

        address coordinator = config.get("bridge_coordinator_l2").toAddress();
        require(coordinator != address(0), "bridge_coordinator_l2 not set");

        address layerzeroAdapter = config.get("layerzero_adapter").toAddress();
        address lineaAdapter = config.get("linea_adapter").toAddress();

        // Unit token checks
        require(GenericUnitL2(unitToken).owner() == coordinator, "unit token owner mismatch");
        // Note: cannot check runtime code of GenericUnitL2 due to immutable args

        // Bridge Coordinator checks
        address coordinatorImpl = address(uint160(uint256(vm.load(coordinator, IMPLEMENTATION_SLOT))));
        require(
            coordinatorImpl.codehash == keccak256(type(BridgeCoordinatorL2).runtimeCode), "coordinator code mismatch"
        );
        require(uint256(vm.load(coordinator, INITIALIZABLE_STORAGE)) == 1, "coordinator not initialized");
        require(BridgeCoordinatorL2(coordinator).genericUnit() == unitToken, "coordinator unit token mismatch");

        // LayerZeroAdapter checks
        if (layerzeroAdapter != address(0)) {
            address bridgeCoordinator = LayerZeroAdapter(layerzeroAdapter).bridgeCoordinator();
            require(bridgeCoordinator == coordinator, "layerzero adapter coordinator mismatch");
        }

        // LineaBridgeAdapter checks
        if (lineaAdapter != address(0)) {
            address bridgeCoordinator = LineaBridgeAdapter(lineaAdapter).bridgeCoordinator();
            require(bridgeCoordinator == coordinator, "linea adapter coordinator mismatch");
        }

        console.log("All checks passed!");
    }
}
