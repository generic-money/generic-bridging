# Contract Specification: LineaBridgeAdapter

## 1. Overview

### Purpose
Fully implemented bridge adapter using Linea's canonical **MessageService** for cross-chain messaging between Ethereum mainnet and Linea L2. This adapter handles message passing between chains - it does NOT hold or manage tokens. The BridgeCoordinator handles all token locking/unlocking, while this adapter sends and receives cross-chain messages via Linea's native bridge infrastructure.

### Key Features
- Fully implements `IBridgeAdapter` interface
- Integrates with Linea's `IMessageService` for cross-chain messaging
- Extends `BaseAdapter` for common adapter functionality
- Implements `ILineaBridgeAdapter` for Linea-specific inbound settlement
- Zero-fee bridging (transactions are sponsored by Linea/Status)

## 2. Core Functionality

### Implementation
Provides a complete implementation of the IBridgeAdapter interface with:
- `bridge()` - Initiates bridge transaction via `_dispatchBridge()`
- `estimateBridgeFee()` - Returns zero fee (transactions are sponsored)
- `bridgeType()` - Returns bridge type identifier (constant `2`)
- `bridgeCoordinator()` - Returns the connected coordinator address (inherited from BaseAdapter)
- `settleInboundBridge()` - Handles inbound messages from Linea MessageService

### State Variables
- `IBridgeCoordinator public immutable coordinator` - Reference to the BridgeCoordinator contract (inherited)
- `uint16 private constant BRIDGE_TYPE = 2` - Unique bridge protocol identifier
- `uint32 public nonce` - Counter for bridge transactions (inherited)
- `mapping(address messageService => uint256 chainId) public messageServiceToChainId` - Maps message service addresses to chain IDs (inherited)
- `mapping(uint256 chainId => address messageService) public chainIdToMessageService` - Maps chain IDs to message service addresses (inherited)

## 3. Constructor

### Parameters
- `_coordinator`: Reference to IBridgeCoordinator for callbacks (passed to BaseAdapter)
- `owner`: Owner address for access control (passed to BaseAdapter)

### Inheritance Chain
- `BaseAdapter(_coordinator, owner)` - Sets up coordinator reference and ownership
- `ILineaBridgeAdapter` - Provides Linea-specific interface for inbound settlements

## 4. Linea Bridge Integration

### Message Handling
- **Outbound**: `_dispatchBridge()` encodes messages and sends via `messageService.sendMessage()`
- **Inbound**: `settleInboundBridge()` receives messages from MessageService and calls `coordinator.settleInboundMessage()`
- **Payload Format**: `abi.encodeCall(ILineaBridgeAdapter.settleInboundBridge, (message, messageId))` - encoded function call with message and ID
- **Fee Structure**: Zero native fee (sponsored transactions up to 250k gas on Linea, >1M gas on Status)

### Chain Configuration
- `setMessageService()` - Configures chain ID to message service mapping (inherited from BaseAdapter)
- Validates configuration consistency and cleans up previous mappings
- Emits `MessageServiceConfigured` event for off-chain tracking

### Security Features
- **Service Validation**: Verifies message service is registered for the source chain
- **Authorization**: Only coordinator can call `bridge()` function, only registered message services can call `settleInboundBridge()`
- **Chain Validation**: Validates chain ID and message service mappings exist
- **Sender Authentication**: Uses `messageService.sender()` to verify remote adapter identity

## 5. Message Flow

### Outbound Flow (L1 → L2):
1. BridgeCoordinator calls `adapter.bridge()` with chain ID, remote adapter, message, and params
2. `_dispatchBridge()` validates destination message service exists
3. Encodes payload as `abi.encodeCall(ILineaBridgeAdapter.settleInboundBridge, (message, messageId))`
4. Calls `messageService.sendMessage()` with remote adapter address, fee, and calldata
5. Linea MessageService delivers message to remote chain adapter
6. Refunds any excess native fee to specified refund address

### Inbound Flow (L2 → L1):
1. Linea MessageService calls `settleInboundBridge()` on destination adapter
2. Adapter validates message service is registered (non-zero chain ID mapping)
3. Retrieves remote sender address using `messageService.sender()`
4. Calls `coordinator.settleInboundMessage()` with bridge type, chain ID, sender, message, and ID
5. Coordinator handles token operations (minting/unlocking)

### Fee Estimation
1. `estimateBridgeFee()` always returns `0` regardless of parameters
2. Transactions are sponsored by Linea (up to 250k gas) and Status (>1M gas)
3. Sponsored gas limits exceed expected execution requirements for L2 proxy operations

## 6. Implemented Security Features

- **Service Authorization**: `UnauthorizedCaller` error prevents messages from unregistered message services
- **Chain Validation**: Requires valid message service mappings for both directions
- **Access Control**: Only coordinator can initiate bridge transactions (`UnauthorizedCaller` error)
- **Message-only Architecture**: Adapter never holds tokens, only passes messages
- **Fee Refund Protection**: `FeeRefundFailed` error ensures excess fees are properly returned
- **Parameter Validation**: `InvalidParams` and `InsufficientFee` errors for malformed requests

## 7. Events

- `MessageServiceConfigured(uint256 indexed chainId, address indexed previousService, address indexed newService)` - Chain configuration updates (inherited from BaseAdapter)

## 8. Error Handling

- `InvalidParams()` - Arbitrary calldata does not match expected encoding format
- `InsufficientFee()` - Provided fee is insufficient for bridge operation (though typically zero)
- `FeeRefundFailed()` - Refunding excess fee to refund address failed
- `InvalidZeroAddress()` - Zero address validation (inherited from BaseAdapter)
- `UnauthorizedCaller()` - Access control violation (inherited from BaseAdapter)

## 9. Fee Structure & Sponsorship

### Zero-Fee Design
- `estimateBridgeFee()` hardcoded to return `0`
- Transactions sponsored by Linea and Status networks
- Gas limits: 250k on Linea, >1M on Status
- Sufficient for expected L2 proxy execution requirements

### Refund Mechanism
- Accepts native ETH for future compatibility
- Automatically refunds excess fees to specified refund address
- Uses low-level call with success validation for refund safety

## 10. Linea-Specific Implementation Details

### MessageService Integration
- Directly integrates with Linea's canonical `IMessageService`
- Uses `sendMessage()` for outbound messages with fee and calldata
- Validates inbound messages through registered service mappings
- Retrieves remote sender using `messageService.sender()` for authentication

### Address Encoding
- Uses `Bytes32AddressLib.toAddressFromLowBytes()` for remote adapter conversion
- Uses `Bytes32AddressLib.toBytes32WithLowAddress()` for sender encoding
- Maintains compatibility with coordinator's bytes32 addressing scheme

### Chain Configuration
- Supports multiple chains through message service registration
- Owner-only configuration with automatic cleanup of previous mappings
- Bidirectional mapping for efficient lookup in both directions
