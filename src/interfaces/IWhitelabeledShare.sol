// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IWhitelabeledShare
 * @notice Interface for whitelabeled share tokens that wrap underlying vault shares
 * @dev This interface defines the core functionality for wrapping and unwrapping share tokens
 * within the Generic Protocol ecosystem.
 */
interface IWhitelabeledShare {
    /**
     * @notice Emitted when underlying share tokens are wrapped into whitelabeled tokens
     * @param owner The address that received the newly minted whitelabeled tokens
     * @param amount The quantity of tokens wrapped (same amount of underlying tokens consumed and whitelabeled tokens
     * minted)
     */
    event Wrapped(address indexed owner, uint256 amount);
    /**
     * @notice Emitted when whitelabeled tokens are unwrapped back to underlying share tokens
     * @param owner The address that owned the whitelabeled tokens during the unwrap
     * @param recipient The address that received the underlying share tokens
     * @param amount The quantity of tokens unwrapped (same amount of whitelabeled tokens burned and underlying tokens
     * released)
     */
    event Unwrapped(address indexed owner, address indexed recipient, uint256 amount);

    /**
     * @notice Wraps underlying share tokens into whitelabeled tokens for a specified owner
     * @dev Transfers `amount` of underlying share tokens from the caller to this contract
     * and mints an equivalent amount of whitelabeled tokens to the `owner` address.
     * This maintains 1:1 parity between underlying shares and whitelabeled tokens.
     * @param owner The address that will receive the minted whitelabeled tokens
     * @param amount The amount of underlying share tokens to wrap and whitelabeled tokens to mint
     */
    function wrap(address owner, uint256 amount) external;

    /**
     * @notice Unwraps whitelabeled tokens back to underlying share tokens
     * @dev Burns `amount` of whitelabeled tokens from the owner's balance
     * and transfers an equivalent amount of underlying share tokens to the recipient.
     * This maintains the 1:1 parity in reverse direction.
     * If the caller is not the owner, the caller must have sufficient allowance to burn the owner's tokens.
     * @param owner The address that owns the whitelabeled tokens to be unwrapped
     * @param recipient The address that will receive the underlying share tokens
     * @param amount The amount of whitelabeled tokens to burn and share tokens to receive
     */
    function unwrap(address owner, address recipient, uint256 amount) external;

    /**
     * @notice Returns the address of the underlying share token that this contract wraps
     * @dev This is the ERC20 token address of the vault shares that back the whitelabeled tokens.
     * The underlying token typically represents claims on protocol vault positions and
     * may accrue yield over time through vault strategy operations.
     * @return The contract address of the underlying share token
     */
    function shareToken() external view returns (address);
}
