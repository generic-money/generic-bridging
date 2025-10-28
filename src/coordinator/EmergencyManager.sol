// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseBridgeCoordinator } from "./BaseBridgeCoordinator.sol";

abstract contract EmergencyManager is BaseBridgeCoordinator {
    /**
     * @notice The role that manages emergency actions
     */
    bytes32 public constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");

    /**
     * @notice Emergency function to forcefully remove a local bridge adapter configuration
     * @dev Only callable by EMERGENCY_MANAGER_ROLE. Use with extreme caution as this will prevent any operations using
     * this adapter
     * @param bridgeType The identifier for the bridge protocol
     */
    function forceRemoveLocalBridgeAdapter(uint16 bridgeType) external onlyRole(EMERGENCY_MANAGER_ROLE) {
        delete bridgeTypes[bridgeType].local.adapter;
    }

    /**
     * @notice Emergency function to forcefully remove a remote bridge adapter configuration
     * @dev Only callable by EMERGENCY_MANAGER_ROLE. Use with extreme caution as this will prevent any operations using
     * this adapter
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The remote chain ID
     */
    function forceRemoveRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId
    )
        external
        onlyRole(EMERGENCY_MANAGER_ROLE)
    {
        delete bridgeTypes[bridgeType].remote[chainId].adapter;
    }

    /**
     * @notice Emergency function to forcefully remove a local bridge adapter from the inbound-only list
     * @dev Only callable by EMERGENCY_MANAGER_ROLE. Use with extreme caution as this will prevent any pending inbound
     * operations from this adapter
     * @param bridgeType The identifier for the bridge protocol
     * @param adapter The local bridge adapter address to remove from inbound-only list
     */
    function forceRemoveInboundOnlyLocalBridgeAdapter(
        uint16 bridgeType,
        address adapter
    )
        external
        onlyRole(EMERGENCY_MANAGER_ROLE)
    {
        delete bridgeTypes[bridgeType].local.isInboundOnly[adapter];
    }

    /**
     * @notice Emergency function to forcefully remove a remote bridge adapter from the inbound-only list
     * @dev Only callable by EMERGENCY_MANAGER_ROLE. Use with extreme caution as this will prevent any pending inbound
     * operations from this adapter
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The remote chain ID
     * @param adapter The remote bridge adapter address (encoded as bytes32) to remove from inbound-only list
     */
    function forceRemoveInboundOnlyRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter
    )
        external
        onlyRole(EMERGENCY_MANAGER_ROLE)
    {
        delete bridgeTypes[bridgeType].remote[chainId].isInboundOnly[adapter];
    }
}
