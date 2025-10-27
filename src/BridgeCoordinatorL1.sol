// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BridgeCoordinator } from "./coordinator/BridgeCoordinator.sol";
import { PredepositCoordinator } from "./coordinator/PredepositCoordinator.sol";

/**
 * @title BridgeCoordinatorL1
 * @notice L1-specific BridgeCoordinator that includes predeposit functionality
 * @dev Inherits from BridgeCoordinator and PredepositCoordinator to provide full bridge coordination
 * capabilities along with predeposit handling on Layer 1.
 */
contract BridgeCoordinatorL1 is BridgeCoordinator, PredepositCoordinator { }
