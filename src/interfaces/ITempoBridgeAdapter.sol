// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title ITempoBridgeAdapter
 * @notice Standard interface that all bridge adapters deployed on Tempo must implement to integrate with the
 * TempoBridgeCoordinator
 * @dev Adapters handle message passing, not token management. The coordinator controls routing and permissions.
 */
interface ITempoBridgeAdapter {
    /**
     * @notice Dispatches an outbound message through the underlying bridge implementation.
     * @param chainId Destination chain identifier recognised by the adapter implementation.
     * @param remoteAdapter Encoded address or identifier of the remote adapter endpoint.
     * @param message Payload forwarded to the remote coordinator for settlement.
     * @param refundAddress Address to refund any excess fees or failed transactions.
     * @param bridgeParams Adapter-specific parameters used to quote and configure the bridge call.
     * @param messageId Unique identifier for tracking the cross-chain message.
     * @param fee The bridging fee to be supplied alongside the call, as estimated by the adapter.
     */
    function bridge(
        uint256 chainId,
        bytes32 remoteAdapter,
        bytes calldata message,
        address refundAddress,
        bytes calldata bridgeParams,
        bytes32 messageId,
        uint256 fee
    )
        external;

    /**
     * @notice Quotes the bridging fee required to execute a bridge call.
     * @param chainId Destination chain identifier recognised by the adapter implementation.
     * @param message Payload that will be forwarded to the remote coordinator for settlement.
     * @param bridgeParams Adapter-specific parameters used to configure the bridge call.
     * @return nativeFee Amount of LZEndpointDollar (LZD) that must be supplied alongside the call.
     */
    function estimateBridgeFee(
        uint256 chainId,
        bytes calldata message,
        bytes calldata bridgeParams
    )
        external
        view
        returns (uint256 nativeFee);

    /**
     * @notice Returns the unique identifier for the bridge protocol this adapter implements
     * @dev This ensures the coordinator can route messages correctly based on bridge type
     * @return The bridge type as a uint16
     */
    function bridgeType() external view returns (uint16);

    /**
     * @notice Returns the address of the bridge coordinator this adapter is connected to
     * @dev This ensures all adapters maintain a reference to their coordinator for callbacks
     * @return The address of the BridgeCoordinator contract
     */
    function bridgeCoordinator() external view returns (address);
}
