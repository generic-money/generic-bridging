// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { Config } from "forge-std/Config.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BridgeCoordinator } from "../src/coordinator/BridgeCoordinator.sol";
import { BridgeCoordinatorL1 } from "../src/BridgeCoordinatorL1.sol";
import { BridgeCoordinatorL2 } from "../src/BridgeCoordinatorL2.sol";
import { LayerZeroAdapter, IBridgeCoordinator } from "../src/adapters/LayerZeroAdapter.sol";
import { LineaBridgeAdapter } from "../src/adapters/LineaBridgeAdapter.sol";

contract Deploy is Script, Config {
    /// forge script script/Deploy.s.sol:Deploy --sig "bridgeCoordinator()" -f {chain alias}
    function bridgeCoordinator() external {
        _loadConfig("./addrs/external.toml", false);

        address shareToken = config.get("share_token").toAddress();
        require(shareToken != address(0), "share token not set");
        console.log("ShareToken address:", shareToken);

        address admin = config.get("bridging_admin").toAddress();
        require(admin != address(0), "admin not set");
        console.log("Admin address:", admin);

        address rolesAdmin = config.get("bridge_coordinator_roles_admin").toAddress();
        require(rolesAdmin != address(0), "roles admin not set");
        console.log("RolesAdmin address:", rolesAdmin);

        bool isL1 = config.get("is_l1").toBool();
        console.log("Is L1:", isL1);

        _loadConfig("./addrs/deployments.toml", true);

        console.log("----------");
        console.log("New deployments:\n");

        vm.createSelectFork(config.getRpcUrl());
        vm.startBroadcast();

        address coordinatorImpl = isL1 ? address(new BridgeCoordinatorL1()) : address(new BridgeCoordinatorL2());
        address coordinator = address(
            new TransparentUpgradeableProxy(
                coordinatorImpl, admin, abi.encodeCall(BridgeCoordinator.initialize, (shareToken, rolesAdmin))
            )
        );

        vm.stopBroadcast();

        // Note: `[{chain alias or id}.address]` must be present in deployments.toml
        // reverts with ChainNotInitialized error otherwise
        string memory key = isL1 ? "bridge_coordinator_l1" : "bridge_coordinator_l2";
        config.set(key, coordinator);

        string memory desc = isL1 ? "BridgeCoordinatorL1 deployed at" : "BridgeCoordinatorL2 deployed at";
        console.log(desc, coordinator);
    }

    /// forge script script/Deploy.s.sol:Deploy --sig "layerZeroAdapter()" -f {chain alias}
    function layerZeroAdapter() external {
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

        console.log("----------");
        console.log("New deployments:\n");

        vm.createSelectFork(config.getRpcUrl());
        vm.startBroadcast();

        address adapter = address(new LayerZeroAdapter(IBridgeCoordinator(coordinator), admin, lzEndpoint));

        vm.stopBroadcast();

        // Note: `[{chain alias or id}.address]` must be present in deployments.toml
        // reverts with ChainNotInitialized error otherwise
        config.set("layerzero_adapter", adapter);

        console.log("LayerZeroAdapter deployed at:", adapter);
    }

    /// forge script script/Deploy.s.sol:Deploy --sig "lineaAdapter()" -f {chain alias}
    function lineaAdapter() external {
        _loadConfig("./addrs/external.toml", false);

        address admin = config.get("bridging_admin").toAddress();
        require(admin != address(0), "admin not set");
        console.log("Admin address:", admin);

        bool isL1 = config.get("is_l1").toBool();
        console.log("Is L1:", isL1);

        _loadConfig("./addrs/deployments.toml", true);

        string memory key = isL1 ? "bridge_coordinator_l1" : "bridge_coordinator_l2";
        address coordinator = config.get(key).toAddress();
        require(coordinator != address(0), "bridge coordinator not set");
        string memory desc = isL1 ? "BridgeCoordinatorL1 address" : "BridgeCoordinatorL2 address";
        console.log(desc, coordinator);

        console.log("----------");
        console.log("New deployments:\n");

        vm.createSelectFork(config.getRpcUrl());
        vm.startBroadcast();

        address adapter = address(new LineaBridgeAdapter(IBridgeCoordinator(coordinator), admin));

        vm.stopBroadcast();

        // Note: `[{chain alias or id}.address]` must be present in deployments.toml
        // reverts with ChainNotInitialized error otherwise
        config.set("linea_adapter", adapter);

        console.log("LineaBridgeAdapter deployed at:", adapter);
    }
}
