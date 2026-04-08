// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BridgeCoordinatorTempo, BridgeCoordinator } from "../../src/BridgeCoordinatorTempo.sol";

import { BaseBridgeCoordinatorHarness } from "./BaseBridgeCoordinatorHarness.sol";

contract BridgeCoordinatorTempoHarness is BaseBridgeCoordinatorHarness, BridgeCoordinatorTempo {
    function _feeToken() internal virtual override(BridgeCoordinatorTempo, BridgeCoordinator) returns (address) {
        return BridgeCoordinatorTempo._feeToken();
    }
}
