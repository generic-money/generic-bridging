// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseBridgeCoordinator } from "./BaseBridgeCoordinator.sol";

abstract contract BridgeMessageCoordinator is BaseBridgeCoordinator {
    /**
     * @notice Emitted when shares are bridged out to another chain
     * @param sender The address that initiated the bridge operation
     * @param owner The address on this chain on whose behalf the shares are bridged
     * @param remoteRecipient The recipient address on the destination chain (as bytes32)
     * @param amount The amount of shares bridged out
     * @param messageId Unique identifier for tracking the bridge message
     */
    event BridgedOut(
        address sender,
        address indexed owner,
        bytes32 indexed remoteRecipient,
        uint256 amount,
        bytes32 indexed messageId
    );
    /**
     * @notice Emitted when shares are bridged in from another chain
     * @param remoteSender The sender address on the source chain (as bytes32)
     * @param recipient The recipient address on this chain that received the shares
     * @param amount The amount of shares bridged in
     * @param messageId Unique identifier for tracking the bridge message
     */
    event BridgedIn(bytes32 indexed remoteSender, address indexed recipient, uint256 amount, bytes32 indexed messageId);
    /**
     * @notice Emitted when a rollback bridge operation is initiated
     * @param rollbackedMessageId The original message ID that is being rollbacked
     * @param messageId The unique identifier for tracking the rollback message
     */
    event BridgeRollbackedOut(bytes32 indexed rollbackedMessageId, bytes32 indexed messageId);

    /**
     * @notice Thrown when the decoded on-behalf address is zero
     */
    error BridgeMessage_InvalidOnBehalf();
    /**
     * @notice Thrown when the decoded recipient address is zero
     */
    error BridgeMessage_InvalidRecipient();
    /**
     * @notice Thrown when the remote recipient parameter is zero
     */
    error BridgeMessage_InvalidRemoteRecipient();
    /**
     * @notice Thrown when the bridge amount is zero
     */
    error BridgeMessage_InvalidAmount();
    /**
     * @notice Thrown when there is no recorded failed message execution for a given message ID
     */
    error BridgeMessage_NoFailedMessageExecution();
    /**
     * @notice Thrown when the rollback message data does not match a failed message
     */
    error BridgeMessage_InvalidFailedMessageData();
    /**
     * @notice Thrown when the original message is not of type BRIDGE
     */
    error BridgeMessage_InvalidMessageType();
    /**
     * @notice Thrown when there is no sender address to rollback to
     */
    error BridgeMessage_NoSenderToRollback();

    /**
     * @notice Bridges shares to another chain using the specified bridge protocol
     * @dev Restricts shares on this chain and sends a message to release equivalent shares on destination chain
     * @param bridgeType The identifier for the bridge protocol to use (must have registered adapter)
     * @param chainId The destination chain ID
     * @param onBehalf The address on this chain on whose behalf the shares are bridged
     * @param remoteRecipient The recipient address on the destination chain (encoded as bytes32)
     * @param amount The amount of shares to bridge
     * @param bridgeParams Protocol-specific parameters required by the bridge adapter
     * @return messageId Unique identifier for tracking the cross-chain message
     */
    function bridge(
        uint16 bridgeType,
        uint256 chainId,
        address onBehalf,
        bytes32 remoteRecipient,
        uint256 amount,
        bytes calldata bridgeParams
    )
        external
        payable
        nonReentrant
        returns (bytes32 messageId)
    {
        require(onBehalf != address(0), BridgeMessage_InvalidOnBehalf());
        require(remoteRecipient != bytes32(0), BridgeMessage_InvalidRemoteRecipient());
        require(amount > 0, BridgeMessage_InvalidAmount());

        bytes memory bridgeMessageData = encodeBridgeMessage(encodeOmnichainAddress(onBehalf), remoteRecipient, amount);
        messageId = _dispatchMessage(bridgeType, chainId, bridgeMessageData, bridgeParams);

        _restrictTokens(msg.sender, amount);

        emit BridgedOut(msg.sender, onBehalf, remoteRecipient, amount, messageId);
    }

    /**
     * @notice Initiates a rollback of a failed inbound bridge operation
     * @dev Validates the failed message and sends a rollback message to the source chain
     * @param bridgeType The identifier for the bridge protocol to use (must have registered adapter)
     * @param originalChainId The chain id of the failed message
     * @param originalMessageData The original bridge message data that failed execution
     * @param originalMessageId Unique identifier of the original cross-chain message
     * @param bridgeParams Protocol-specific parameters required by the bridge adapter
     * @return rollbackMessageId Unique identifier for tracking the rollback cross-chain message
     */
    function rollback(
        uint16 bridgeType,
        uint256 originalChainId,
        bytes calldata originalMessageData,
        bytes32 originalMessageId,
        bytes calldata bridgeParams
    )
        external
        payable
        nonReentrant
        returns (bytes32 rollbackMessageId)
    {
        bytes32 failedMessageExecution = failedMessageExecutions[originalMessageId];
        require(failedMessageExecution != bytes32(0), BridgeMessage_NoFailedMessageExecution());
        require(
            failedMessageExecution == _failedMessageHash(originalChainId, originalMessageData),
            BridgeMessage_InvalidFailedMessageData()
        );
        delete failedMessageExecutions[originalMessageId];

        Message memory originalMessage = abi.decode(originalMessageData, (Message));
        require(originalMessage.messageType == MessageType.BRIDGE, BridgeMessage_InvalidMessageType());
        BridgeMessage memory bridgeMessage = abi.decode(originalMessage.data, (BridgeMessage));
        require(bridgeMessage.omnichainSender != bytes32(0), BridgeMessage_NoSenderToRollback());

        bytes memory rollbackMessageData =
            encodeBridgeMessage(bytes32(0), bridgeMessage.omnichainSender, bridgeMessage.amount);
        rollbackMessageId = _dispatchMessage(bridgeType, originalChainId, rollbackMessageData, bridgeParams);

        emit BridgedOut(msg.sender, address(0), bridgeMessage.omnichainSender, bridgeMessage.amount, rollbackMessageId);
        emit BridgeRollbackedOut(originalMessageId, rollbackMessageId);
    }

    /**
     * @notice Settles an inbound bridge message
     * @dev Decodes the bridge message and releases shares to the recipient on this chain
     * @param messageData The encoded bridge message containing recipient and amount data
     * @param messageId Unique identifier for tracking the cross-chain message
     */
    function _settleInboundBridgeMessage(bytes memory messageData, bytes32 messageId) internal {
        BridgeMessage memory message = abi.decode(messageData, (BridgeMessage));
        address recipient = decodeOmnichainAddress(message.omnichainRecipient);
        uint256 amount = message.amount;

        require(recipient != address(0), BridgeMessage_InvalidRecipient());
        require(amount > 0, BridgeMessage_InvalidAmount());
        _releaseTokens(recipient, amount);
        emit BridgedIn(message.omnichainSender, recipient, amount, messageId);
    }

    /**
     * @notice Encodes a BRIDGE type message for cross-chain transmission
     * @param remoteSender The address initiating the bridge operation (encoded as bytes32)
     * @param remoteRecipient The recipient address on the destination chain (encoded as bytes32)
     * @param amount The amount of shares to bridge
     */
    function encodeBridgeMessage(
        bytes32 remoteSender,
        bytes32 remoteRecipient,
        uint256 amount
    )
        public
        pure
        returns (bytes memory)
    {
        return abi.encode(
            Message({
                messageType: MessageType.BRIDGE,
                data: abi.encode(
                    BridgeMessage({
                        omnichainSender: remoteSender, omnichainRecipient: remoteRecipient, amount: amount
                    })
                )
            })
        );
    }
}
