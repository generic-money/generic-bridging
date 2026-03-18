// PDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BridgeCoordinator} from "../../coordinator/BridgeCoordinator.sol";
import {IERC20Mintable} from "../../interfaces/IERC20Mintable.sol";
import {IWhitelabeledUnit} from "../../interfaces/IWhitelabeledUnit.sol";
import {ITIP20} from "./interfaces/ITIP20.sol";

/**
 * @title BridgeCoordinatorTempo
 * @notice Tempo-specific implementation of bridge coordinator that burns/mints units (GUSD) instead of transferring
 * @dev Extends BridgeCoordinator with proper token lifecycle management for L2 deployments.
 * Burns units when bridging out and mints units when bridging in, maintaining total supply consistency.
 */
contract BridgeCoordinatorTempo is BridgeCoordinator {
    using SafeERC20 for IERC20;

    /**
     * @notice Generic Protocol doesn't allow whitelabels to be created on Tempo, and therefore you can't redeem either
     */
    error WhitelabelsNotSupported();
    /**
     * @notice Thrown when the coordinator failed to claim the user tokens before burning
     */
    error TransferToCoordinatorFailed();
    /**
     * @notice Thrown when the amount of unit tokens claimed does not match the expected amount
     */
    error IncorrectEscrowBalance();

    /**
     * @notice Burns units when bridging out from L2
     * @dev Overrides base implementation to burn units
     * @param whitelabel Whitelabeled token is unsupported, use zero address for native GUSD token
     * @param owner The address that owns the units to be burned
     * @param amount The amount of units to burn
     */
    function _restrictUnits(
        address whitelabel,
        address owner,
        uint256 amount
    ) internal override {
        if (whitelabel == address(0)) {
            uint256 escrowBalance = ITIP20(genericUnit).balanceOf(
                address(this)
            );
            require(
                ITIP20(genericUnit).transferFrom(owner, address(this), amount),
                TransferToCoordinatorFailed()
            );

            // Tempo TIP-20 transfers can have non-1:1 semantics, so verify exact delivery before burning.
            require(
                ITIP20(genericUnit).balanceOf(address(this)) ==
                    escrowBalance + amount,
                IncorrectEscrowBalance()
            );
            ITIP20(genericUnit).burn(amount);
        } else {
            revert WhitelabelsNotSupported();
        }
    }

    /**
     * @notice Mints units when bridging in to L2
     * @dev Overrides base implementation to mint new units
     * @param whitelabel The whitelabeled unit token address, or zero address for native unit token
     * @param receiver The address that should receive the newly minted units
     * @param amount The amount of units to mint
     */
    function _releaseUnits(
        address whitelabel,
        address receiver,
        uint256 amount
    ) internal override {
        if (whitelabel == address(0)) {
            ITIP20(genericUnit).mint(receiver, amount);
        } else {
            revert WhitelabelsNotSupported();
        }
    }
}
