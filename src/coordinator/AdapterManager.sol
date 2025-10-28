// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseBridgeCoordinator, IBridgeAdapter } from "./BaseBridgeCoordinator.sol";

abstract contract AdapterManager is BaseBridgeCoordinator {
    /**
     * @notice The role that manages bridge configuration
     */
    bytes32 public constant ADAPTER_MANAGER_ROLE = keccak256("ADAPTER_MANAGER_ROLE");

    /**
     * @notice Emitted when a local bridge adapter's inbound-only status is updated
     * @param bridgeType The identifier for the bridge protocol
     * @param adapter The local bridge adapter address
     * @param isInboundOnly Whether the adapter is inbound-only (true) or not (false)
     */
    event LocalInboundOnlyBridgeAdapterUpdated(uint16 indexed bridgeType, address indexed adapter, bool isInboundOnly);
    /**
     * @notice Emitted when a remote bridge adapter's inbound-only status is updated
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The remote chain ID
     * @param adapter The remote bridge adapter address (encoded as bytes32)
     * @param isInboundOnly Whether the adapter is inbound-only (true) or not (false)
     */
    event RemoteInboundOnlyBridgeAdapterUpdated(
        uint16 indexed bridgeType, uint256 indexed chainId, bytes32 indexed adapter, bool isInboundOnly
    );
    /**
     * @notice Emitted when the outbound local bridge adapter is updated
     * @param bridgeType The identifier for the bridge protocol
     * @param adapter The new local bridge adapter address
     */
    event LocalOutboundBridgeAdapterUpdated(uint16 indexed bridgeType, address indexed adapter);
    /**
     * @notice Emitted when the outbound remote bridge adapter is updated
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The remote chain ID
     * @param adapter The new remote bridge adapter address (encoded as bytes32)
     */
    event RemoteOutboundBridgeAdapterUpdated(
        uint16 indexed bridgeType, uint256 indexed chainId, bytes32 indexed adapter
    );

    /**
     * @notice Thrown when bridge adapter's coordinator doesn't match this contract
     */
    error CoordinatorMismatch();
    /**
     * @notice Thrown when bridge adapter's type doesn't match the expected type
     */
    error BridgeTypeMismatch();
    /**
     * @notice Thrown when attempting to swap inbound adapter that is not in the inbound-only list
     */
    error AdapterNotInInboundList();

    /**
     * @notice Sets a local bridge adapter into inbound-only list for a specific bridge type
     * @dev Only callable by ADAPTER_MANAGER_ROLE. Validates adapter configuration if non-zero address provided.
     * When replacing an existing adapter, the old adapter is marked as inbound-only to prevent disruption of pending
     * operations
     * @param bridgeType The identifier for the bridge protocol
     * @param adapter The local bridge adapter address to mark as inbound-only
     * @param isInboundOnly Whether to mark the adapter as inbound-only (true) or remove it from inbound-only list
     * (false)
     */
    function setIsInboundOnlyLocalBridgeAdapter(
        uint16 bridgeType,
        IBridgeAdapter adapter,
        bool isInboundOnly
    )
        external
        onlyRole(ADAPTER_MANAGER_ROLE)
    {
        if (isInboundOnly) {
            require(adapter.bridgeCoordinator() == address(this), CoordinatorMismatch());
            require(adapter.bridgeType() == bridgeType, BridgeTypeMismatch());
        }
        bridgeTypes[bridgeType].local.isInboundOnly[address(adapter)] = isInboundOnly;
        emit LocalInboundOnlyBridgeAdapterUpdated(bridgeType, address(adapter), isInboundOnly);
    }

    /**
     * @notice Sets a remote bridge adapter into inbound-only list for a specific bridge type and chain
     * @dev Only callable by ADAPTER_MANAGER_ROLE.
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The destination chain ID
     * @param adapter The remote bridge adapter address (encoded as bytes32) to mark as inbound-only
     * @param isInboundOnly Whether to mark the adapter as inbound-only (true) or remove it from inbound-only list
     * (false)
     */
    function setIsInboundOnlyRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter,
        bool isInboundOnly
    )
        external
        onlyRole(ADAPTER_MANAGER_ROLE)
    {
        bridgeTypes[bridgeType].remote[chainId].isInboundOnly[adapter] = isInboundOnly;
        emit RemoteInboundOnlyBridgeAdapterUpdated(bridgeType, chainId, adapter, isInboundOnly);
    }

    /**
     * @notice Swaps an existing inbound-only adapter for the outbound local bridge adapter for a specific bridge type
     * @dev Only callable by ADAPTER_MANAGER_ROLE. Previous adapter is marked as inbound-only.
     * @param bridgeType The identifier for the bridge protocol
     * @param adapter The new local bridge adapter contract
     */
    function swapOutboundLocalBridgeAdapter(
        uint16 bridgeType,
        IBridgeAdapter adapter
    )
        external
        onlyRole(ADAPTER_MANAGER_ROLE)
    {
        LocalConfig storage config = bridgeTypes[bridgeType].local;
        if (address(adapter) != address(0)) {
            require(config.isInboundOnly[address(adapter)], AdapterNotInInboundList());
            config.isInboundOnly[address(adapter)] = false;
            emit LocalInboundOnlyBridgeAdapterUpdated(bridgeType, address(adapter), false);
        }
        address oldAdapter = address(config.adapter);
        if (oldAdapter != address(0)) {
            config.isInboundOnly[oldAdapter] = true;
            emit LocalInboundOnlyBridgeAdapterUpdated(bridgeType, oldAdapter, true);
        }
        config.adapter = adapter;
        emit LocalOutboundBridgeAdapterUpdated(bridgeType, address(adapter));
    }

    /**
     * @notice Swaps an existing inbound-only adapter for the outbound remote bridge adapter for a specific bridge type
     * and chain
     * @dev Only callable by ADAPTER_MANAGER_ROLE. Previous adapter is marked as inbound-only.
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The destination chain ID
     * @param adapter The new remote bridge adapter address (encoded as bytes32)
     */
    function swapOutboundRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter
    )
        external
        onlyRole(ADAPTER_MANAGER_ROLE)
    {
        RemoteConfig storage config = bridgeTypes[bridgeType].remote[chainId];
        if (adapter != bytes32(0)) {
            require(config.isInboundOnly[adapter], AdapterNotInInboundList());
            config.isInboundOnly[adapter] = false;
            emit RemoteInboundOnlyBridgeAdapterUpdated(bridgeType, chainId, adapter, false);
        }
        bytes32 oldAdapter = config.adapter;
        if (oldAdapter != bytes32(0)) {
            config.isInboundOnly[oldAdapter] = true;
            emit RemoteInboundOnlyBridgeAdapterUpdated(bridgeType, chainId, oldAdapter, true);
        }
        config.adapter = adapter;
        emit RemoteOutboundBridgeAdapterUpdated(bridgeType, chainId, adapter);
    }
}
