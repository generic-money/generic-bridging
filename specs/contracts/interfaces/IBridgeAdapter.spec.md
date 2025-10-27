# Interface Specification: IBridgeAdapter

## 1. Overview

### Purpose
Standard interface that all bridge adapters must implement to integrate with the BridgeCoordinator. This ensures consistent interaction patterns regardless of the underlying bridge protocol (LayerZero, CCTP, native bridges, etc.). Adapters handle message passing, not token management. The coordinator controls routing and permissions.

## 2. Interface Definition

```solidity
interface IBridgeAdapter {
    // Core bridging function
    function bridge(
        uint256 chainId,
        bytes32 remoteAdapter,
        bytes calldata message,
        address refundAddress,
        bytes calldata bridgeParams
    ) external payable returns (bytes32 messageId);

    // Fee estimation
    function estimateBridgeFee(
        uint256 chainId,
        bytes calldata message,
        bytes calldata bridgeParams
    ) external view returns (uint256 nativeFee);

    // Bridge type identifier
    function bridgeType() external view returns (uint16);

    // Coordinator reference
    function bridgeCoordinator() external view returns (address);
}
```

## 3. Function Descriptions

### bridge()
```solidity
function bridge(
    uint256 chainId,
    bytes32 remoteAdapter,
    bytes calldata message,
    address refundAddress,
    bytes calldata bridgeParams
) external payable returns (bytes32 messageId);
```
Dispatches an outbound message through the underlying bridge implementation. The adapter handles protocol-specific message encoding and transmission. Parameters:
- `chainId`: Destination chain identifier recognised by the adapter implementation
- `remoteAdapter`: Encoded address or identifier of the remote adapter endpoint that will receive the message
- `message`: Payload forwarded to the remote coordinator for settlement
- `refundAddress`: Address to refund any excess fees or failed transactions
- `bridgeParams`: Adapter-specific parameters used to quote and configure the bridge call
- Returns: Identifier returned by the bridge transport for reconciliation

### estimateBridgeFee()
```solidity
function estimateBridgeFee(
    uint256 chainId,
    bytes calldata message,
    bytes calldata bridgeParams
) external view returns (uint256 nativeFee);
```
Quotes the native fee required to execute a bridge call. Used by the coordinator to calculate costs before executing bridge operations. Parameters:
- `chainId`: Destination chain identifier recognised by the adapter implementation
- `message`: Payload that will be forwarded to the remote coordinator for settlement (affects fee calculation)
- `bridgeParams`: Adapter-specific parameters used to configure the bridge call (may affect fee calculation)
- Returns: Amount of native currency that must be supplied alongside the call

### bridgeType()
```solidity
function bridgeType() external view returns (uint16);
```
Returns the unique identifier for the bridge protocol this adapter implements. This ensures the coordinator can route messages correctly based on bridge type.

### bridgeCoordinator()
```solidity
function bridgeCoordinator() external view returns (address);
```
Returns the address of the bridge coordinator this adapter is connected to. This ensures all adapters maintain a reference to their coordinator for callbacks.

## 4. Implementation Architecture

### BaseAdapter Pattern
The protocol provides a `BaseAdapter` abstract contract that implements common functionality for all bridge adapters:

- **Access Control**: Ensures only the coordinator can call bridge functions
- **Message ID Generation**: Creates unique message identifiers
- **Nonce Tracking**: Maintains a counter for bridge transactions to ensure unique message IDs
- **Message Service Management**: Maps chain IDs to message service contracts and provides configuration functions

Concrete implementations must:
1. Extend `BaseAdapter`
2. Implement `_dispatchBridge()` for protocol-specific message sending and fee refunding
3. Implement `estimateBridgeFee()` for fee calculation
4. Define a unique `BRIDGE_TYPE` constant

### Example Implementation Structure
```solidity
contract LineaBridgeAdapter is BaseAdapter, ILineaBridgeAdapter {
    uint16 private constant BRIDGE_TYPE = 2;

    function _dispatchBridge(...) internal override {
        // Protocol-specific bridge logic
        // Handle fee refunding
    }

    function estimateBridgeFee(...) public pure returns (uint256) {
        // Protocol-specific fee calculation
    }

    function bridgeType() public pure override returns (uint16) {
        return BRIDGE_TYPE;
    }
}
```

## 5. Implementation Requirements

### Core Requirements
- Adapters handle message passing, not token management
- Must implement all four interface functions: `bridge()`, `estimateBridgeFee()`, `bridgeType()`, and `bridgeCoordinator()`
- Should validate message parameters and revert with clear error messages for invalid inputs
- Must return a unique `messageId` for tracking cross-chain messages
- Should handle protocol-specific encoding/decoding of messages and parameters
- Must implement proper refund logic for excess fees sent to the `refundAddress`
- Only the configured coordinator should be able to call the `bridge()` function (enforced via access control)

### Integration Requirements
- `bridgeType()` must return a consistent uint16 identifier for the protocol
- `bridgeCoordinator()` must return the address of the coordinator that deployed/configured the adapter
- Adapters should be stateless regarding routing decisions - the coordinator controls which chains are supported
- Fee estimation should be accurate to prevent transaction failures due to insufficient fees
- Implementations typically extend `BaseAdapter` which provides common functionality like nonce tracking, message service management, and coordinator reference

### Security Considerations
- Only the configured coordinator should be able to call `bridge()` function
- Adapters should validate that `remoteAdapter` addresses are properly formatted for the destination chain
- Protocol-specific validation should be performed on `bridgeParams` to prevent malicious usage
- Excess fee refunding must be handled securely with proper error handling
- Message service endpoints must be properly whitelisted and validated to prevent unauthorized inbound messages
- Implementations should check for sufficient fees before attempting bridge operations
