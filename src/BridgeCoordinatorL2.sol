// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BridgeCoordinator, IWhitelabeledShare, SafeERC20, IERC20 } from "./coordinator/BridgeCoordinator.sol";
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
    function _restrictTokens(address whitelabel, address owner, uint256 amount) internal override {
        if (whitelabel == address(0)) {
            IERC20Mintable(shareToken).burn(owner, address(this), amount);
        } else {
            IWhitelabeledShare(whitelabel).unwrap(owner, address(this), amount);
            IERC20Mintable(shareToken).burn(address(this), address(this), amount);
        }
    }

    /**
     * @notice Mints tokens when bridging in to L2
     * @dev Overrides base implementation to mint new tokens instead of transferring from coordinator
     * @param receiver The address that should receive the newly minted tokens
     * @param amount The amount of tokens to mint
     */
    function _releaseTokens(address whitelabel, address receiver, uint256 amount) internal override {
        if (whitelabel == address(0)) {
            IERC20Mintable(shareToken).mint(receiver, amount);
        } else {
            IERC20Mintable(shareToken).mint(address(this), amount);
            SafeERC20.forceApprove(IERC20(shareToken), address(whitelabel), amount);
            IWhitelabeledShare(whitelabel).wrap(receiver, amount);
        }
    }
}
