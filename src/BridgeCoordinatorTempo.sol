// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { BridgeCoordinator, BaseBridgeCoordinator } from "./coordinator/BridgeCoordinator.sol";
import { ITIP20Mintable } from "./interfaces/ITIP20Mintable.sol";

/**
 * @title BridgeCoordinatorTempo
 * @notice Tempo-specific implementation of bridge coordinator that mints TIP-20 tokens
 * @dev Extends BridgeCoordinator with proper token lifecycle management for Tempo deployments.
 * Tracks virtual units when bridging in and out, maintaining total supply consistency.
 */
contract BridgeCoordinatorTempo is BridgeCoordinator {
    using SafeERC20 for IERC20;

    /**
     * @notice Factor to convert between 18 decimals used for units and 6 decimals used for TIP-20 tokens
     */
    uint256 public constant DECIMALS_DELTA_FACTOR = 1e12;
    /**
     * @notice LZEndpointDollar (LZD) token used for fees on Tempo
     */
    IERC20 public constant LZD_TOKEN = IERC20(0x0cEb237E109eE22374a567c6b09F373C73FA4cBb);

    /**
     * @notice Thrown when the whitelabel address is missing for Tempo bridging operations
     */
    error MissingWhitelabelAddress();
    /**
     * @notice Thrown when there are insufficient units to bridge out from Tempo
     */
    error InsufficientUnitsToBridgeOut();
    /**
     * @notice Thrown when decimals rounding results in zero TIP-20 tokens, preventing bridging operations
     */
    error DecimalsRoundingToZero();

    /// @inheritdoc BaseBridgeCoordinator
    // forge-lint: disable-next-line(mixed-case-function)
    function NATIVE_BRIDGING_FEES() public pure override returns (bool) {
        return false;
    }

    /// @inheritdoc BridgeCoordinator
    function _pullFeeTokenFor(address from, uint256 amount, address adapter) internal virtual override {
        LZD_TOKEN.safeTransferFrom(from, address(this), amount);
        LZD_TOKEN.approve(adapter, amount);
    }

    /**
     * @notice Burns units when bridging out from Tempo
     * @dev Overrides base implementation to burn units
     * @param whitelabel The whitelabeled unit token address
     * @param owner The address that owns the units to be burned
     * @param amount The amount of units to burn
     */
    function _restrictUnits(address whitelabel, address owner, uint256 amount) internal override {
        require(whitelabel != address(0), MissingWhitelabelAddress());
        require(unitBalanceOf[whitelabel] >= amount, InsufficientUnitsToBridgeOut());
        unitBalanceOf[whitelabel] -= amount;

        uint256 tip20Amount = amount / DECIMALS_DELTA_FACTOR; // Downscale from units 18 to TIP-20 fixed 6 decimals
        require(tip20Amount > 0, DecimalsRoundingToZero());
        IERC20(whitelabel).safeTransferFrom(owner, address(this), tip20Amount);
        ITIP20Mintable(whitelabel).burn(tip20Amount);
    }

    /**
     * @notice Mints units when bridging in to Tempo
     * @dev Overrides base implementation to mint new units
     * @param whitelabel The whitelabeled unit token address
     * @param receiver The address that should receive the newly minted units
     * @param amount The amount of units to mint
     */
    function _releaseUnits(address whitelabel, address receiver, uint256 amount) internal override {
        require(whitelabel != address(0), MissingWhitelabelAddress());
        unitBalanceOf[whitelabel] += amount;

        uint256 tip20Amount = amount / DECIMALS_DELTA_FACTOR; // Downscale from units 18 to TIP-20 fixed 6 decimals
        require(tip20Amount > 0, DecimalsRoundingToZero());
        ITIP20Mintable(whitelabel).mint(receiver, tip20Amount);
    }
}
