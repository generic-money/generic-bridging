// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BridgeCoordinatorL2 } from "../../src/BridgeCoordinatorL2.sol";
import { IBridgeAdapter } from "../../src/interfaces/IBridgeAdapter.sol";

contract BridgeCoordinatorL2Harness is BridgeCoordinatorL2 {
    function exposed_initializableStorageSlot() external pure returns (bytes32) {
        return _initializableStorageSlot();
    }

    function workaround_setOutboundLocalBridgeAdapter(uint16 bridgeType, address adapter) external {
        bridgeTypes[bridgeType].local.adapter = IBridgeAdapter(adapter);
    }

    function workaround_setOutboundRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter
    )
        external
    {
        bridgeTypes[bridgeType].remote[chainId].adapter = adapter;
    }
}
