// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { BaseBridgeCoordinator, IBridgeAdapter } from "./BaseBridgeCoordinator.sol";
import { AdapterManager } from "./AdapterManager.sol";
import { EmergencyManager } from "./EmergencyManager.sol";
import { BridgeMessageCoordinator } from "./BridgeMessageCoordinator.sol";
import { IWhitelabeledShare } from "../interfaces/IWhitelabeledShare.sol";

/**
 * @title BridgeCoordinator
 * @notice Coordinates cross-chain bridging of share tokens through multiple bridge protocols
 * @dev Base implementation that handles routing between bridge adapters and manages cross-chain operations.
 * Inheriting contracts should override _restrictTokens and _releaseTokens for custom token logic.
 */
contract BridgeCoordinator is BaseBridgeCoordinator, AdapterManager, EmergencyManager, BridgeMessageCoordinator {
    using SafeERC20 for IERC20;

    /**
     * @notice Emitted when a cross-chain message is dispatched
     * @param bridgeType The type of bridge protocol used for the operation
     * @param destChainId The destination chain ID
     * @param messageId Unique identifier for tracking the cross-chain message
     */
    event MessageOut(
        uint16 indexed bridgeType, uint256 indexed destChainId, bytes32 indexed messageId, bytes messageData
    );
    /**
     * @notice Emitted when a cross-chain message is received
     * @param bridgeType The type of bridge protocol used for the operation
     * @param srcChainId The source chain ID
     * @param messageId Unique identifier for tracking the cross-chain message
     */
    event MessageIn(
        uint16 indexed bridgeType, uint256 indexed srcChainId, bytes32 indexed messageId, bytes messageData
    );
    /**
     * @notice Emitted when execution of an inbound message fails
     * @param messageId Unique identifier for tracking the failed message
     */
    event MessageExecutionFailed(bytes32 indexed messageId);

    /**
     * @notice Thrown when share token address is zero during initialization
     */
    error ZeroShareToken();
    /**
     * @notice Thrown when admin address is zero during initialization
     */
    error ZeroAdmin();
    /**
     * @notice Thrown when no local bridge adapter is configured for the specified bridge type
     */
    error NoLocalBridgeAdapter();
    /**
     * @notice Thrown when no remote bridge adapter is configured for the bridge type and chain ID
     */
    error NoRemoteBridgeAdapter();
    /**
     * @notice Thrown when caller is not the expected local bridge adapter
     */
    error OnlyLocalAdapter();
    /**
     * @notice Thrown when remote sender is not the expected remote bridge adapter
     */
    error OnlyRemoteAdapter();
    /**
     * @notice Thrown when tryReleaseTokens is called by an external address
     */
    error CallerNotSelf();
    /**
     * @notice Thrown when an unsupported message type is encountered during inbound settlement
     */
    error UnsupportedMessageType(uint8 messageType);

    /**
     * @notice Constructor that disables initializers for the implementation contract
     * @dev Prevents the implementation contract from being initialized directly
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the BridgeCoordinator with share token and admin
     * @dev Can only be called once due to initializer modifier
     * @param _shareToken The address of the share token to be managed by this coordinator
     * @param _admin The address to be granted DEFAULT_ADMIN_ROLE for managing the coordinator
     */
    function initialize(address _shareToken, address _admin) external initializer {
        require(_shareToken != address(0), ZeroShareToken());
        require(_admin != address(0), ZeroAdmin());
        shareToken = _shareToken;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Dispatches a cross-chain message via the specified bridge adapter
     * @dev Internal function called by bridge and rollback functions to send messages
     * @param bridgeType The identifier for the bridge protocol to use
     * @param chainId The destination chain ID
     * @param messageData The encoded bridge message data to be sent
     * @param bridgeParams Protocol-specific parameters required by the bridge adapter
     * @return messageId Unique identifier for tracking the cross-chain message
     */
    function _dispatchMessage(
        uint16 bridgeType,
        uint256 chainId,
        bytes memory messageData,
        bytes calldata bridgeParams
    )
        internal
        override
        returns (bytes32 messageId)
    {
        IBridgeAdapter adapter = bridgeTypes[bridgeType].local.adapter;
        bytes32 remoteAdapter = bridgeTypes[bridgeType].remote[chainId].adapter;
        require(address(adapter) != address(0), NoLocalBridgeAdapter());
        require(remoteAdapter != bytes32(0), NoRemoteBridgeAdapter());

        messageId = adapter.bridge{ value: msg.value }(chainId, remoteAdapter, messageData, msg.sender, bridgeParams);

        emit MessageOut(bridgeType, chainId, messageId, messageData);
    }

    /**
     * @notice Settles an inbound message
     * @dev Called by bridge adapters (either current or inbound-only) when receiving cross-chain messages.
     * Validates that both the calling adapter and remote sender are authorized for the bridge type and chain
     * @param bridgeType The identifier for the bridge protocol that received the message
     * @param chainId The source chain ID where the bridge operation originated
     * @param remoteSender The original sender address on the source chain (encoded as bytes32)
     * @param messageData The encoded bridge message containing recipient and amount data
     * @param messageId Unique identifier for tracking the cross-chain message
     */
    function settleInboundMessage(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 remoteSender,
        bytes calldata messageData,
        bytes32 messageId
    )
        external
        nonReentrant
    {
        LocalConfig storage localConfig = bridgeTypes[bridgeType].local;
        require(msg.sender == address(localConfig.adapter) || localConfig.isInboundOnly[msg.sender], OnlyLocalAdapter());
        RemoteConfig storage remoteConfig = bridgeTypes[bridgeType].remote[chainId];
        require(remoteSender == remoteConfig.adapter || remoteConfig.isInboundOnly[remoteSender], OnlyRemoteAdapter());

        emit MessageIn(bridgeType, chainId, messageId, messageData);

        try this.trySettleInboundMessage(messageData, messageId) { }
        catch {
            failedMessageExecutions[messageId] = _failedMessageHash(chainId, messageData);
            emit MessageExecutionFailed(messageId);
        }
    }

    /**
     * @dev Attempts to settle an inbound cross-chain message by executing the contained call data
     * @notice This function processes incoming messages from other chains and executes the payload
     * @param messageData The inbound message containing execution parameters and call data
     * @param messageId Unique identifier for tracking the cross-chain message
     */
    function trySettleInboundMessage(bytes calldata messageData, bytes32 messageId) external {
        require(msg.sender == address(this), CallerNotSelf());

        Message memory message = abi.decode(messageData, (Message));
        if (message.messageType == MessageType.BRIDGE) {
            _settleInboundBridgeMessage(message.data, messageId);
        } else {
            revert UnsupportedMessageType(uint8(message.messageType));
        }
    }

    /**
     * @notice Lock tokens when bridging out
     * @param whitelabel The whitelabeled share token address, or zero address for native share token
     * @param owner The address that owns the tokens to be restricted
     * @param amount The amount of tokens to restrict
     */
    function _restrictTokens(address whitelabel, address owner, uint256 amount) internal virtual override {
        if (whitelabel == address(0)) {
            IERC20(shareToken).safeTransferFrom(owner, address(this), amount);
        } else {
            IWhitelabeledShare(whitelabel).unwrap(owner, address(this), amount);
        }
    }

    /**
     * @notice Unlock tokens when bridging in
     * @param whitelabel The whitelabeled share token address, or zero address for native share token
     * @param receiver The address that should receive the released tokens
     * @param amount The amount of tokens to release
     */
    function _releaseTokens(address whitelabel, address receiver, uint256 amount) internal virtual override {
        if (whitelabel == address(0)) {
            IERC20(shareToken).safeTransfer(receiver, amount);
        } else {
            IERC20(shareToken).forceApprove(address(whitelabel), amount);
            IWhitelabeledShare(whitelabel).wrap(receiver, amount);
        }
    }
}
