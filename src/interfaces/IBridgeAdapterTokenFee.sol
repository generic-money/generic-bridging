// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IBridgeAdapter } from "./IBridgeAdapter.sol";

/**
 * @title IBridgeAdapterTokenFee
 * @notice Standard interface that all bridge adapters using token to pay for fees must implement to integrate with the
 * BridgeCoordinator
 */
interface IBridgeAdapterTokenFee is IBridgeAdapter {
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
}
