// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IBridgeAdapter } from "../interfaces/IBridgeAdapter.sol";
import { IBridgeCoordinator } from "../interfaces/IBridgeCoordinator.sol";

/**
 * @title BaseAdapter
 * @notice Abstract base contract for bridge adapters that provides common functionality
 * @dev Implements standard adapter properties and coordinator reference. Inheriting contracts
 * must implement the bridge and estimateBridgeFee functions for specific bridge protocols.
 */
abstract contract BaseAdapter is IBridgeAdapter, Ownable2Step {
    /**
     * @notice Thrown when an operation receives the zero address where a contract is required.
     */
    error InvalidZeroAddress();
    /**
     * @notice Thrown when a non-authorised caller attempts to invoke restricted functionality.
     */
    error UnauthorizedCaller();

    /**
     * @notice The bridge coordinator contract that this adapter is connected to
     */
    address public immutable bridgeCoordinator;

    /**
     * @notice Initializes the base adapter with bridge type and coordinator
     * @param _coordinator The bridge coordinator contract address
     */
    constructor(IBridgeCoordinator _coordinator, address owner) Ownable(owner) {
        bridgeCoordinator = address(_coordinator);
    }
}
