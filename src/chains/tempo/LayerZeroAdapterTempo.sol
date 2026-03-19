// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Origin, MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

import { IBridgeCoordinator } from "../../adapters/BaseAdapter.sol";
import { BridgeMessage, Message, MessageType } from "../../coordinator/Message.sol";
import { LayerZeroAdapterTempoBase } from "./LayerZeroAdapterTempoBase.sol";

/**
 * @title LayerZeroAdapterTempo
 * @notice LayerZero adapter for Tempo
 * @dev Tempo uses 6-decimal local amounts, while bridge messages use 18-decimal amounts. This contract only changes
 * the send and receive paths where that conversion happens.
 */
contract LayerZeroAdapterTempo is LayerZeroAdapterTempoBase {
    uint256 internal constant LOCAL_TO_CANONICAL_SCALE = 1e12;

    /**
     * @notice Sets the coordinator, owner, and LayerZero endpoint
     * @param _coordinator Bridge coordinator allowed to send and settle messages
     * @param owner Address that manages peers and endpoint ids
     * @param endpoint LayerZero endpoint for this chain
     */
    constructor(
        IBridgeCoordinator _coordinator,
        address owner,
        address endpoint
    )
        LayerZeroAdapterTempoBase(_coordinator, owner, endpoint)
    { }

    /**
     * @notice Sends an outbound message from Tempo
     * @dev BRIDGE amounts are scaled from local 6-decimal units to canonical 18-decimal units before send.
     * @param chainId Destination chain id
     * @param remoteAdapter Remote adapter registered in the coordinator
     * @param message Encoded message using Tempo-local amounts
     * @param refundAddress Address that receives any leftover native fee
     * @param bridgeParams LayerZero options
     * @param messageId Message id from the coordinator
     */
    function bridge(
        uint256 chainId,
        bytes32 remoteAdapter,
        bytes calldata message,
        address refundAddress,
        bytes calldata bridgeParams,
        bytes32 messageId
    )
        external
        payable
        override
    {
        require(msg.sender == bridgeCoordinator, UnauthorizedCaller());

        uint32 dstEid = chainIdToEndpointId[chainId];
        require(dstEid != 0, InvalidZeroAddress());

        bytes32 configuredPeer = _getPeerOrRevert(dstEid);
        require(configuredPeer == remoteAdapter, PeersMismatch(configuredPeer, remoteAdapter));

        // Tempo-only change: scale BRIDGE amounts from local 6 decimals to canonical 18 decimals.
        bytes memory payload = abi.encode(_toCanonicalMessage(message), messageId);
        bytes memory options = combineOptions(dstEid, SEND, bridgeParams);

        _lzSend(dstEid, payload, options, MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 }), refundAddress);
    }

    /**
     * @notice Receives an inbound message for Tempo
     * @dev BRIDGE amounts are scaled from canonical 18-decimal units down to local 6-decimal units before settle.
     * Amounts smaller than one local base unit are dropped as dust.
     * @param origin LayerZero metadata for the source chain and sender
     * @param guid LayerZero packet id
     * @param payload Encoded bridge payload and message id
     */
    function _lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata payload,
        address,
        bytes calldata
    )
        internal
        override
    {
        uint256 chainId = endpointIdToChainId[origin.srcEid];
        require(chainId != 0, InvalidZeroAddress());

        (bytes memory messageData, bytes32 messageId) = abi.decode(payload, (bytes, bytes32));
        // Tempo-only change: scale inbound BRIDGE amounts from canonical 18 decimals down to local 6 decimals.
        bytes memory normalizedMessageData = _toLocalMessage(messageData);

        if (normalizedMessageData.length != 0) {
            IBridgeCoordinator(bridgeCoordinator)
                .settleInboundMessage(bridgeType(), chainId, origin.sender, normalizedMessageData, messageId);
        }

        emit MessageGuidRecorded(messageId, guid, chainId, origin.srcEid);
    }

    /**
     * @notice Scales a BRIDGE payload from Tempo-local units to canonical units
     * @dev Non-BRIDGE messages are passed through unchanged.
     * @param messageData Encoded message using Tempo-local amounts
     * @return normalizedMessage Encoded message using canonical 18-decimal amounts
     */
    function _toCanonicalMessage(bytes calldata messageData) internal pure returns (bytes memory) {
        Message memory message = abi.decode(messageData, (Message));
        if (message.messageType != MessageType.BRIDGE) {
            return messageData;
        }

        BridgeMessage memory bridgeMessage = abi.decode(message.data, (BridgeMessage));
        // Tempo uses 6-decimal local amounts, but the wire format stays at 18 decimals.
        bridgeMessage.amount *= LOCAL_TO_CANONICAL_SCALE;

        return abi.encode(Message({ messageType: message.messageType, data: abi.encode(bridgeMessage) }));
    }

    /**
     * @notice Scales a BRIDGE payload from canonical units to Tempo-local units
     * @dev Non-BRIDGE messages are passed through unchanged. Dust smaller than one local unit is dropped.
     * @param messageData Encoded message using canonical 18-decimal amounts
     * @return normalizedMessage Encoded message using local 6-decimal amounts, or empty bytes if only dust remains
     */
    function _toLocalMessage(bytes memory messageData) internal pure returns (bytes memory) {
        Message memory message = abi.decode(messageData, (Message));
        if (message.messageType != MessageType.BRIDGE) {
            return messageData;
        }

        BridgeMessage memory bridgeMessage = abi.decode(message.data, (BridgeMessage));
        bridgeMessage.amount /= LOCAL_TO_CANONICAL_SCALE;

        if (bridgeMessage.amount == 0) {
            // Drop dust that is too small to represent in Tempo local units.
            return bytes("");
        }

        return abi.encode(Message({ messageType: message.messageType, data: abi.encode(bridgeMessage) }));
    }
}
