// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseAdapter } from "./BaseAdapter.sol";
import { IBridgeCoordinator } from "../interfaces/IBridgeCoordinator.sol";
import { IBridgeAdapter } from "../interfaces/IBridgeAdapter.sol";
import { IMessageService } from "../interfaces/bridges/linea/IMessageService.sol";
import { ILineaBridgeAdapter } from "../interfaces/bridges/linea/ILineaBridgeAdapter.sol";
import { Bytes32AddressLib } from "../utils/Bytes32AddressLib.sol";
import { BridgeTypes } from "./BridgeTypes.sol";

contract LineaBridgeAdapter is BaseAdapter, ILineaBridgeAdapter {
    /**
     * @notice Thrown when arbitrary calldata does not match the expected encoding format.
     */
    error InvalidParams();
    /**
     * @notice Thrown when the provided fee is insufficient for the bridge operation
     */
    error InsufficientFee();
    /**
     * @notice Thrown when refunding excess fee fails
     */
    error FeeRefundFailed();

    constructor(IBridgeCoordinator _coordinator, address owner) BaseAdapter(_coordinator, owner) { }

    /// @inheritdoc BaseAdapter
    function _dispatchBridge(
        uint256 chainId,
        bytes32 remoteAdapter,
        bytes calldata message,
        address refundAddress,
        bytes calldata bridgeParams,
        bytes32 messageId
    )
        internal
        virtual
        override
    {
        IMessageService messageService = IMessageService(chainIdToMessageService[chainId]);
        require(address(messageService) != address(0), InvalidZeroAddress());

        bytes memory calldata_ = abi.encodeCall(ILineaBridgeAdapter.settleInboundBridge, (message, messageId));
        uint256 fee = estimateBridgeFee(chainId, message, bridgeParams);
        require(msg.value >= fee, InsufficientFee());

        messageService.sendMessage{ value: fee }(Bytes32AddressLib.toAddressFromLowBytes(remoteAdapter), fee, calldata_);

        if (msg.value > fee) {
            // Refund any excess fee to the refund address
            (bool success,) = payable(refundAddress).call{ value: msg.value - fee }("");
            require(success, FeeRefundFailed());
        }
    }

    /// @inheritdoc ILineaBridgeAdapter
    function settleInboundBridge(bytes calldata messageData, bytes32 messageId) external {
        IMessageService messageService = IMessageService(msg.sender);
        uint256 chainId = messageServiceToChainId[address(messageService)];

        // If the chain detected is 0, it means the message service isn't whitelisted
        require(chainId != 0, UnauthorizedCaller());

        bytes32 remoteSender = Bytes32AddressLib.toBytes32WithLowAddress(messageService.sender());
        coordinator.settleInboundMessage(bridgeType(), chainId, remoteSender, messageData, messageId);
    }

    /// @inheritdoc IBridgeAdapter
    function estimateBridgeFee(uint256, bytes calldata, bytes calldata) public pure returns (uint256 nativeFee) {
        // IMPORTANT: This is hardcoded to 0 because both Linea and Status sponsor transaction on their end.
        // The transactions sponsored on Linea can spend up to 250k gas, more than a million on Status end, which is
        // higher than the expected execution from our L2 proxy.
        return 0;
    }

    /// @inheritdoc BaseAdapter
    function bridgeType() public pure override returns (uint16) {
        return BridgeTypes.LINEA;
    }
}
