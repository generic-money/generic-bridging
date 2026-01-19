// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { Config } from "forge-std/Config.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { GenericUnitL2 } from "lib/generic-protocol/src/unit/GenericUnitL2.sol";

import { BridgeCoordinator } from "../src/coordinator/BridgeCoordinator.sol";
import { BridgeCoordinatorL2 } from "../src/BridgeCoordinatorL2.sol";
import { LayerZeroAdapter } from "../src/adapters/LayerZeroAdapter.sol";
import { LineaBridgeAdapter } from "../src/adapters/LineaBridgeAdapter.sol";

/// @dev `[{chain alias or id}.address]` must be present in deployments.toml
/// otherwise config.set() reverts with ChainNotInitialized error
contract Deploy is Script, Config {
    /// forge script script/Deploy.s.sol:Deploy --sig "deployL2()" --chain-id {chain id}
    function deployL2() external {
        _loadConfig("./addrs/external.toml", false);

        bool isL1 = config.get("is_l1").toBool();
        require(!isL1, "Not L2 deployment");

        bool deployLayerzeroAdapter = config.get("deploy_layerzero_adapter").toBool();
        console.log("Deploy LayerZeroAdapter:", deployLayerzeroAdapter);

        bool deployLineaAdapter = config.get("deploy_linea_adapter").toBool();
        console.log("Deploy LineaBridgeAdapter:", deployLineaAdapter);

        address admin = config.get("bridging_admin").toAddress();
        require(admin != address(0), "admin not set");
        console.log("Admin address:", admin);

        address coordinatorRolesAdmin = config.get("bridge_coordinator_roles_admin").toAddress();
        require(coordinatorRolesAdmin != address(0), "roles admin not set");
        console.log("Coordinator roles admin address:", coordinatorRolesAdmin);

        address lzEndpoint = config.get("layerzero_endpoint").toAddress();
        require(!deployLayerzeroAdapter || lzEndpoint != address(0), "layerzero endpoint not set");
        console.log("LayerZero Endpoint address:", lzEndpoint);

        address coordinatorAdapterManager = config.get("bridge_coordinator_adapter_manager").toAddress();
        require(coordinatorAdapterManager != address(0), "adapter manager not set");
        console.log("Coordinator adapter manager address:", coordinatorAdapterManager);

        _loadConfig("./addrs/deployments.toml", true);

        vm.createSelectFork(config.getRpcUrl());
        vm.startBroadcast();

        // Deploy BridgeCoordinator
        address coordinatorImpl = address(new BridgeCoordinatorL2());
        address coordinator = address(new TransparentUpgradeableProxy(coordinatorImpl, admin, ""));

        // Deploy GenericUnitL2 for the coordinator
        address unitToken = address(new GenericUnitL2(coordinator, "Generic USD Unit", "G_USD_U"));

        // Initialize BridgeCoordinator with caller as initial admin
        BridgeCoordinator(coordinator).initialize(unitToken, msg.sender);

        // Deploy LayerZeroAdapter
        address layerZeroAdapter;
        if (deployLayerzeroAdapter) {
            layerZeroAdapter = address(new LayerZeroAdapter(BridgeCoordinator(coordinator), admin, lzEndpoint));
        }

        // Deploy LineaBridgeAdapter
        address lineaAdapter;
        if (deployLineaAdapter) {
            lineaAdapter = address(new LineaBridgeAdapter(BridgeCoordinator(coordinator), admin));
        }

        // Grant ADAPTER_MANAGER_ROLE
        BridgeCoordinator(coordinator)
            .grantRole(BridgeCoordinator(coordinator).ADAPTER_MANAGER_ROLE(), coordinatorAdapterManager);
        console.log("BridgeCoordinator ADAPTER_MANAGER_ROLE granted to:", coordinatorAdapterManager);

        // Transfer DEFAULT_ADMIN_ROLE
        if (msg.sender != coordinatorRolesAdmin) {
            BridgeCoordinator(coordinator)
                .grantRole(BridgeCoordinator(coordinator).DEFAULT_ADMIN_ROLE(), coordinatorRolesAdmin);
            BridgeCoordinator(coordinator).revokeRole(BridgeCoordinator(coordinator).DEFAULT_ADMIN_ROLE(), msg.sender);
        }
        console.log("BridgeCoordinator DEFAULT_ADMIN_ROLE granted to:", coordinatorRolesAdmin);

        vm.stopBroadcast();

        // Save addresses to deployments.toml
        config.set("generic_unit_l2", unitToken);
        config.set("bridge_coordinator_l2", coordinator);
        config.set("layerzero_adapter", layerZeroAdapter);
        config.set("linea_adapter", lineaAdapter);

        // Log deployed addresses
        console.log("----------");
        console.log("New deployments:\n");

        console.log("GenericUnitL2 deployed at", unitToken);
        console.log("BridgeCoordinatorL2 deployed at", coordinator);
        if (layerZeroAdapter != address(0)) {
            console.log("LayerZeroAdapter deployed at:", layerZeroAdapter);
        } else {
            console.log("LayerZeroAdapter deployment skipped (endpoint address not set)");
        }
        if (lineaAdapter != address(0)) {
            console.log("LineaBridgeAdapter deployed at:", lineaAdapter);
        } else {
            console.log("LineaBridgeAdapter deployment skipped");
        }
    }

    /// forge script script/Deploy.s.sol:Deploy --sig "deployLayerZeroAdapter()" --chain-id {chain id}
    function deployLayerZeroAdapter() external {
        _loadConfig("./addrs/external.toml", false);

        address admin = config.get("bridging_admin").toAddress();
        require(admin != address(0), "admin not set");
        console.log("Admin address:", admin);

        address lzEndpoint = config.get("layerzero_endpoint").toAddress();
        require(lzEndpoint != address(0), "layerzero endpoint not set");
        console.log("LayerZero Endpoint address:", lzEndpoint);

        bool isL1 = config.get("is_l1").toBool();
        console.log("Is L1:", isL1);

        _loadConfig("./addrs/deployments.toml", true);

        string memory key = isL1 ? "bridge_coordinator_l1" : "bridge_coordinator_l2";
        address coordinator = config.get(key).toAddress();
        require(coordinator != address(0), "bridge coordinator not set");
        string memory desc = isL1 ? "BridgeCoordinatorL1 address" : "BridgeCoordinatorL2 address";
        console.log(desc, coordinator);

        vm.createSelectFork(config.getRpcUrl());
        vm.startBroadcast();

        // Deploy LayerZeroAdapter
        address adapter = address(new LayerZeroAdapter(BridgeCoordinator(coordinator), admin, lzEndpoint));

        vm.stopBroadcast();

        // Save address to deployments.toml
        config.set("layerzero_adapter", adapter);

        // Log deployed address
        console.log("----------");
        console.log("New deployments:\n");

        console.log("LayerZeroAdapter deployed at:", adapter);
    }
}
