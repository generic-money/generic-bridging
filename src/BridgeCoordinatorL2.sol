// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { BridgeCoordinator } from "./coordinator/BridgeCoordinator.sol";
import { IERC20Mintable } from "./interfaces/IERC20Mintable.sol";
import { IWhitelabeledShare } from "./interfaces/IWhitelabeledShare.sol";

/**
 * @title BridgeCoordinatorL2
 * @notice L2-specific implementation of bridge coordinator that burns/mints shares instead of transferring
 * @dev Extends BridgeCoordinator with proper token lifecycle management for L2 deployments.
 * Burns shares when bridging out and mints shares when bridging in, maintaining total supply consistency.
 */
contract BridgeCoordinatorL2 is BridgeCoordinator {
    using SafeERC20 for IERC20;

    /**
     * @notice Burns shares when bridging out from L2
     * @dev Overrides base implementation to burn shares
     * @param whitelabel The whitelabeled share token address, or zero address for native share token
     * @param owner The address that owns the shares to be burned
     * @param amount The amount of shares to burn
     */
    function _restrictShares(address whitelabel, address owner, uint256 amount) internal override {
        if (whitelabel == address(0)) {
            IERC20Mintable(shareToken).burn(owner, address(this), amount);
        } else {
            IWhitelabeledShare(whitelabel).unwrap(owner, address(this), amount);
            IERC20Mintable(shareToken).burn(address(this), address(this), amount);
        }

        // Note: Burn would fail if unwrapping did not transfer the correct amount
    }

    /**
     * @notice Mints shares when bridging in to L2
     * @dev Overrides base implementation to mint new shares
     * @param whitelabel The whitelabeled share token address, or zero address for native share token
     * @param receiver The address that should receive the newly minted shares
     * @param amount The amount of shares to mint
     */
    function _releaseShares(address whitelabel, address receiver, uint256 amount) internal override {
        if (whitelabel == address(0)) {
            IERC20Mintable(shareToken).mint(receiver, amount);
        } else {
            IERC20Mintable(shareToken).mint(address(this), amount);
            IERC20(shareToken).forceApprove(address(whitelabel), amount);
            IWhitelabeledShare(whitelabel).wrap(receiver, amount);
        }
    }
}
