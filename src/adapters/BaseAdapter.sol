// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IBridgeAdapter } from "../interfaces/IBridgeAdapter.sol";
import { IBridgeCoordinator } from "../interfaces/IBridgeCoordinator.sol";

/**
 * @title BaseAdapter
 * @notice Abstract base contract for bridge adapters that provides common functionality
 * @dev Implements standard adapter properties and coordinator reference. Inheriting contracts
 * must implement the bridge and estimateBridgeFee functions for specific bridge protocols.
 */
abstract contract BaseAdapter is IBridgeAdapter, Ownable2Step {
    /**
     * @notice Thrown when an operation receives the zero address where a contract is required.
     */
    error InvalidZeroAddress();
    /**
     * @notice Thrown when a non-authorised caller attempts to invoke restricted functionality.
     */
    error UnauthorizedCaller();

    /**
     * @notice Emitted whenever the message service endpoint configured for a chain changes.
     * @param chainId The L2 chain identifier associated with the message service.
     * @param previousService The previously configured message service address.
     * @param newService The newly configured message service address.
     */
    event MessageServiceConfigured(
        uint256 indexed chainId, address indexed previousService, address indexed newService
    );

    /**
     * @notice The bridge coordinator contract that this adapter is connected to
     */
    IBridgeCoordinator public immutable coordinator;
    /**
     * @notice Reverse lookup for authorised message services back to their origin chain id.
     */
    mapping(address messageService => uint256 chainId) public messageServiceToChainId;
    /**
     * @notice Mapping from chain id to the trusted message service contract.
     */
    mapping(uint256 chainId => address messageService) public chainIdToMessageService;

    /**
     * @notice Counter for the amount of bridging transactions done by the adapter
     */
    uint32 public nonce;

    /**
     * @notice Initializes the base adapter with bridge type and coordinator
     * @param _coordinator The bridge coordinator contract address
     */
    constructor(IBridgeCoordinator _coordinator, address owner) Ownable(owner) {
        coordinator = _coordinator;
    }

    /**
     * @notice Returns the address of the bridge coordinator this adapter is connected to
     * @return The address of the bridge coordinator contract
     */
    function bridgeCoordinator() external view override returns (address) {
        return address(coordinator);
    }

    function bridgeType() public view virtual returns (uint16);

    /**
     * @notice Returns the messageId for the bridging and receiving of the units
     * @param chainId The destination chain ID for the bridge operation
     * @return The bytes32 encoded messageId of the bridge transaction
     */
    function getMessageId(uint256 chainId) public view returns (bytes32) {
        // forge-lint: disable-next-line(asm-keccak256)
        return keccak256(abi.encodePacked(chainId, bridgeType(), block.timestamp, nonce));
    }

    /**
     * @notice Updates the message service endpoint used for cross-chain messaging.
     * @dev Callable only by owner.
     * @param _messageService The new message service contract.
     */
    function setMessageService(address _messageService, uint256 _chainId) external onlyOwner {
        require(_messageService != address(0), InvalidZeroAddress());

        // We need to clean up the previous messageService if it exists
        address previousService = chainIdToMessageService[_chainId];

        emit MessageServiceConfigured(_chainId, previousService, _messageService);

        if (previousService != address(0)) {
            messageServiceToChainId[previousService] = 0;
        }
        messageServiceToChainId[_messageService] = _chainId;
        chainIdToMessageService[_chainId] = _messageService;
    }

    /// @inheritdoc IBridgeAdapter
    function bridge(
        uint256 chainId,
        bytes32 remoteAdapter,
        bytes calldata message,
        address refundAddress,
        bytes calldata bridgeParams
    )
        external
        payable
        returns (bytes32 messageId)
    {
        require(msg.sender == address(coordinator), UnauthorizedCaller());

        messageId = getMessageId(chainId);
        unchecked {
            ++nonce;
        }

        _dispatchBridge(chainId, remoteAdapter, message, refundAddress, bridgeParams, messageId);
    }

    /**
     * @notice Dispatches an outbound message through the underlying bridge implementation.
     * @param chainId Destination chain identifier recognised by the adapter implementation.
     * @param remoteAdapter Encoded address or identifier of the remote adapter endpoint.
     * @param message Payload forwarded to the remote coordinator for settlement.
     * @param refundAddress Address to refund any excess fees or failed transactions.
     * @param bridgeParams Adapter-specific parameters used to quote and configure the bridge call.
     * @param messageId The internal only message id for the transaction
     */
    function _dispatchBridge(
        uint256 chainId,
        bytes32 remoteAdapter,
        bytes calldata message,
        address refundAddress,
        bytes calldata bridgeParams,
        bytes32 messageId
    )
        internal
        virtual;
}
