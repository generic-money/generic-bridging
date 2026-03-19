// PDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BridgeCoordinator } from "../../coordinator/BridgeCoordinator.sol";
import { ITIP20 } from "./interfaces/ITIP20.sol";

/**
 * @title BridgeCoordinatorTempo
 * @notice Tempo bridge coordinator
 * @dev Burns and mints the local TIP-20 unit token instead of escrowing ERC-20 balances.
 */
contract BridgeCoordinatorTempo is BridgeCoordinator {
    /**
     * @notice Tempo does not support whitelabel units
     */
    error WhitelabelsNotSupported();
    /**
     * @notice The coordinator could not pull the user's tokens before burning
     */
    error TransferToCoordinatorFailed();
    /**
     * @notice The TIP-20 balance delta did not match the requested amount
     */
    error IncorrectEscrowBalance();

    /**
     * @notice Burns units on Tempo when bridging out
     * @dev The amount is already in local TIP-20 units. LayerZeroAdapterTempo handles the decimal conversion.
     * @param whitelabel Must be zero because Tempo does not support whitelabel units
     * @param owner Address to pull tokens from before burning
     * @param amount Local TIP-20 amount to burn
     */
    function _restrictUnits(address whitelabel, address owner, uint256 amount) internal override {
        if (whitelabel == address(0)) {
            uint256 escrowBalance = ITIP20(genericUnit).balanceOf(address(this));
            require(ITIP20(genericUnit).transferFrom(owner, address(this), amount), TransferToCoordinatorFailed());

            // Amounts here are local TIP-20 units. The Tempo adapter does the 6<->18 decimal conversion.
            // Some TIP-20s can charge fees or add rewards on transfer, so check the balance delta before burning.
            require(ITIP20(genericUnit).balanceOf(address(this)) == escrowBalance + amount, IncorrectEscrowBalance());
            ITIP20(genericUnit).burn(amount);
        } else {
            revert WhitelabelsNotSupported();
        }
    }

    /**
     * @notice Mints units on Tempo when bridging in
     * @dev The Tempo adapter has already converted the amount into local TIP-20 units.
     * @param whitelabel Must be zero because Tempo does not support whitelabel units
     * @param receiver Address that receives the minted tokens
     * @param amount Local TIP-20 amount to mint
     */
    function _releaseUnits(address whitelabel, address receiver, uint256 amount) internal override {
        if (whitelabel == address(0)) {
            ITIP20(genericUnit).mint(receiver, amount);
        } else {
            revert WhitelabelsNotSupported();
        }
    }
}
