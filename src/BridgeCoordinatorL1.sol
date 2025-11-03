// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { BridgeCoordinator } from "./coordinator/BridgeCoordinator.sol";
import { PredepositCoordinator } from "./coordinator/PredepositCoordinator.sol";
import { IWhitelabeledUnit } from "./interfaces/IWhitelabeledUnit.sol";

/**
 * @title BridgeCoordinatorL1
 * @notice L1-specific BridgeCoordinator that includes predeposit functionality and handles share locking/unlocking
 * @dev Inherits from BridgeCoordinator and PredepositCoordinator to provide full bridge coordination
 * capabilities along with predeposit handling on Layer 1. Implements share restriction and release logic
 * by transferring shares to/from the coordinator contract, with support for whitelabeled shares.
 */
contract BridgeCoordinatorL1 is BridgeCoordinator, PredepositCoordinator {
    using SafeERC20 for IERC20;

    /**
     * @notice Thrown when the amount of share tokens restricted does not match the expected amount
     */
    error IncorrectEscrowBalance();

    /**
     * @notice Lock shares when bridging out
     * @dev This function implements additional validation layers since whitelabel shares could potentially
     * be malicious or poorly implemented.
     * @param whitelabel The whitelabeled share token address, or zero address for native share token
     * @param owner The address that owns the shares to be restricted
     * @param amount The amount of shares to restrict
     */
    function _restrictShares(address whitelabel, address owner, uint256 amount) internal override {
        uint256 escrowBalance = IERC20(shareToken).balanceOf(address(this));
        if (whitelabel == address(0)) {
            IERC20(shareToken).safeTransferFrom(owner, address(this), amount);
        } else {
            IWhitelabeledUnit(whitelabel).unwrap(owner, address(this), amount);
        }

        // Note: Sanity check that the expected amount of shares were actually transferred
        // Whitelabeled shares could have faulty implementations that do not transfer the correct amount
        require(IERC20(shareToken).balanceOf(address(this)) == escrowBalance + amount, IncorrectEscrowBalance());
    }

    /**
     * @notice Unlock shares when bridging in
     * @param whitelabel The whitelabeled share token address, or zero address for native share token
     * @param receiver The address that should receive the released shares
     * @param amount The amount of shares to release
     */
    function _releaseShares(address whitelabel, address receiver, uint256 amount) internal override {
        if (whitelabel == address(0)) {
            IERC20(shareToken).safeTransfer(receiver, amount);
        } else {
            IERC20(shareToken).forceApprove(address(whitelabel), amount);
            IWhitelabeledUnit(whitelabel).wrap(receiver, amount);
        }
    }
}
