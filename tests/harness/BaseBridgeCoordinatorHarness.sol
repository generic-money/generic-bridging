// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BridgeCoordinator, IBridgeAdapter } from "../../src/coordinator/BridgeCoordinator.sol";

abstract contract BaseBridgeCoordinatorHarness is BridgeCoordinator {
    function exposed_restrictShares(address whitelabel, address owner, uint256 amount) external {
        _restrictShares(whitelabel, owner, amount);
    }

    function exposed_releaseShares(address whitelabel, address receiver, uint256 amount) external {
        _releaseShares(whitelabel, receiver, amount);
    }

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

    function workaround_setIsInboundOnlyLocalBridgeAdapter(
        uint16 bridgeType,
        address adapter,
        bool isInboundOnly
    )
        external
    {
        bridgeTypes[bridgeType].local.isInboundOnly[adapter] = isInboundOnly;
    }

    function workaround_setIsInboundOnlyRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter,
        bool isInboundOnly
    )
        external
    {
        bridgeTypes[bridgeType].remote[chainId].isInboundOnly[adapter] = isInboundOnly;
    }

    function workaround_setFailedMessageExecution(bytes32 messageId, bytes32 messageHash) external {
        failedMessageExecutions[messageId] = messageHash;
    }
}
