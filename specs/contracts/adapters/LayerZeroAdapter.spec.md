# Contract Specification: LayerZeroAdapter

## 1. Overview

### Purpose
Fully implemented bridge adapter using LayerZero's **OApp** (Omnichain Application) for cross-chain messaging. This adapter handles message passing between chains - it does NOT hold or manage tokens. The BridgeCoordinator handles all token locking/unlocking, while this adapter sends and receives cross-chain messages via LayerZero.

### Key Features
- Fully implements `IBridgeAdapter` interface
- Inherits from LayerZero **OApp** for cross-chain messaging
- Extends `BaseAdapter` for common adapter functionality
- Uses `OAppOptionsType3` for gas configuration options

## 2. Core Functionality

### Implementation
Provides a complete implementation of the IBridgeAdapter interface with:
- `bridge()` - Initiates bridge transaction via `_dispatchBridge()`
- `estimateBridgeFee()` - Returns LayerZero fee estimate using `_quote()`
- `bridgeType()` - Returns bridge type identifier (constant `1`)
- `bridgeCoordinator()` - Returns the connected coordinator address (inherited from BaseAdapter)

### State Variables
- `IBridgeCoordinator public immutable coordinator` - Reference to the BridgeCoordinator contract (inherited)
- `uint16 public constant BRIDGE_TYPE = 1` - Unique bridge protocol identifier
- `uint16 public constant SEND = 1` - Message type for OAppOptionsType3
- `uint32 public nonce` - Counter for bridge transactions (inherited)
- `mapping(uint256 chainId => uint32 eid) public chainIdToEndpointId` - Maps chain IDs to LayerZero endpoint IDs
- `mapping(uint32 eid => uint256 chainId) public endpointIdToChainId` - Reverse lookup from endpoint to chain ID

## 3. Constructor

### Parameters
- `_coordinator`: Reference to IBridgeCoordinator for callbacks (passed to BaseAdapter)
- `owner`: Owner address for access control (passed to both BaseAdapter and OApp)
- `endpoint`: LayerZero endpoint contract address (passed to OApp)

### Inheritance Chain
- `BaseAdapter(_coordinator, owner)` - Sets up coordinator reference and ownership
- `OApp(endpoint, owner)` - Initializes LayerZero messaging functionality

## 4. LayerZero Integration

### Message Handling
- **Outbound**: `_dispatchBridge()` encodes messages and sends via `_lzSend()`
- **Inbound**: `_lzReceive()` decodes messages and calls `coordinator.settleInboundMessage()`
- **Payload Format**: `abi.encode(message, messageId)` - contains coordinator message and internal ID
- **Options**: Uses `OAppOptionsType3.combineOptions()` for gas configuration per chain

### Chain Configuration
- `setRemoteEndpointConfig()` - Configures chain ID to endpoint ID mapping and sets LayerZero peer
- Validates configuration consistency and cleans up previous mappings
- Emits `EndpointIdConfigured` event for off-chain tracking

### Security Features
- **Peer Validation**: Verifies configured LayerZero peer matches coordinator's remote adapter
- **Authorization**: Only coordinator can call `bridge()` function
- **Chain Validation**: Validates chain ID and endpoint ID mappings exist

## 5. Message Flow

### Outbound Flow (L1 → L2):
1. BridgeCoordinator calls `adapter.bridge()` with chain ID, remote adapter, message, and params
2. `_dispatchBridge()` validates destination endpoint and peer configuration
3. Encodes payload as `abi.encode(message, messageId)`
4. Calls `_lzSend()` with destination endpoint, payload, and gas options
5. LayerZero delivers message to remote chain adapter
6. Emits `MessageGuidRecorded` with correlation between internal ID and LayerZero GUID

### Inbound Flow (L2 → L1):
1. LayerZero endpoint calls `_lzReceive()` on destination adapter
2. Adapter validates source chain mapping from endpoint ID
3. Decodes payload to extract coordinator message and message ID
4. Calls `coordinator.settleInboundMessage()` with bridge type, chain ID, sender, message, and ID
5. Coordinator handles token operations (minting/unlocking)
6. Emits `MessageGuidRecorded` for tracking

### Fee Estimation
1. `estimateBridgeFee()` creates message payload with current nonce-based message ID
2. Uses `combineOptions()` to merge bridge params with default gas settings
3. Calls LayerZero's `_quote()` to get native fee estimate
4. Returns fee amount for transaction planning

## 6. Implemented Security Features

- **Peer Validation**: `PeersMismatch` error prevents messages from unconfigured adapters
- **Chain Validation**: Requires valid endpoint ID mappings for both directions
- **Access Control**: Only coordinator can initiate bridge transactions (`UnauthorizedCaller` error)
- **Message-only Architecture**: Adapter never holds tokens, only passes messages
- **Ownership Resolution**: Resolves diamond inheritance pattern to maintain `Ownable2Step` semantics

## 7. Events

- `EndpointIdConfigured(uint256 indexed chainId, uint32 indexed endpointId)` - Chain configuration updates
- `MessageGuidRecorded(bytes32 indexed messageId, bytes32 indexed guid, uint256 indexed chainId, uint32 endpointId)` - Message correlation tracking

## 8. Error Handling

- `PeersMismatch(bytes32 configuredPeer, bytes32 coordinatorAdapter)` - Peer configuration mismatch
- `InvalidZeroAddress()` - Zero address validation (inherited from BaseAdapter)
- `UnauthorizedCaller()` - Access control violation (inherited from BaseAdapter)
