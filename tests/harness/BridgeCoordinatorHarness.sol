// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BridgeCoordinator, IBridgeAdapter } from "../../src/coordinator/BridgeCoordinator.sol";

contract BridgeCoordinatorHarness is BridgeCoordinator {
    struct LastRestrictCall {
        address whitelabel;
        address owner;
        uint256 amount;
    }
    LastRestrictCall public lastRestrictCall;

    function _restrictShares(address whitelabel, address owner, uint256 amount) internal override {
        lastRestrictCall = LastRestrictCall({ whitelabel: whitelabel, owner: owner, amount: amount });
    }

    struct LastReleaseCall {
        address whitelabel;
        address receiver;
        uint256 amount;
    }
    LastReleaseCall public lastReleaseCall;

    function _releaseShares(address whitelabel, address receiver, uint256 amount) internal override {
        lastReleaseCall = LastReleaseCall({ whitelabel: whitelabel, receiver: receiver, amount: amount });
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
