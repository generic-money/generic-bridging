// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IBridgeAdapter
 * @notice Standard interface that all bridge adapters must implement to integrate with the BridgeCoordinator
 * @dev Adapters handle message passing, not token management. The coordinator controls routing and permissions.
 */
interface IBridgeAdapter {
    /**
     * @notice Indicates whether the adapter expects native fees or token fees
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function NATIVE_BRIDGING_FEES() external pure returns (bool);

    /**
     * @notice Quotes the native fee required to execute a bridge call.
     * @param chainId Destination chain identifier recognised by the adapter implementation.
     * @param message Payload that will be forwarded to the remote coordinator for settlement.
     * @param bridgeParams Adapter-specific parameters used to configure the bridge call.
     * @return nativeFee Amount of native currency that must be supplied alongside the call.
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
