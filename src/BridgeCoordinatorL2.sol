// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BridgeCoordinator } from "./coordinator/BridgeCoordinator.sol";
import { IERC20Mintable } from "./interfaces/IERC20Mintable.sol";

/**
 * @title BridgeCoordinatorL2
 * @notice L2-specific implementation of bridge coordinator that burns/mints tokens instead of transferring
 * @dev Extends BridgeCoordinator with proper token lifecycle management for L2 deployments.
 * Burns tokens when bridging out and mints tokens when bridging in, maintaining total supply consistency.
 */
contract BridgeCoordinatorL2 is BridgeCoordinator {
    /**
     * @notice Burns tokens when bridging out from L2
     * @dev Overrides base implementation to burn tokens instead of transferring to coordinator
     * @param owner The address that owns the tokens to be burned
     * @param amount The amount of tokens to burn
     */
    function _restrictTokens(address owner, uint256 amount) internal override {
        IERC20Mintable(shareToken).burn(owner, owner, amount);
    }

    /**
     * @notice Mints tokens when bridging in to L2
     * @dev Overrides base implementation to mint new tokens instead of transferring from coordinator
     * @param receiver The address that should receive the newly minted tokens
     * @param amount The amount of tokens to mint
     */
    function _releaseTokens(address receiver, uint256 amount) internal override {
        IERC20Mintable(shareToken).mint(receiver, amount);
    }
}
