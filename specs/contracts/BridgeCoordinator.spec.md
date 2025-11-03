# Contract Specification: BridgeCoordinator

## 1. Purpose & Context
The BridgeCoordinator ecosystem consists of multiple coordinator contracts that manage cross-chain bridging of unit tokens through various bridge protocols.

- **BridgeCoordinatorL1**: L1-specific coordinator that includes predeposit functionality for early chain deployments
- **BridgeCoordinatorL2**: L2-specific coordinator that burns/mints tokens instead of transferring for proper supply management
- **BridgeCoordinator**: Base coordinator that handles token locking/unlocking and message routing

The coordinators orchestrate message dispatch to bridge adapters (e.g., LayerZero) while maintaining token supply consistency across chains as described in `specs/whitepaper-v1.0.md`.

## 2. Contract Architecture
The system uses a modular architecture with the following components:

### Core Components
- **BaseBridgeCoordinator**: Base contract defining core data structures and interfaces
- **BridgeCoordinator**: Main implementation with token lock/unlock logic
- **AdapterManager**: Manages bridge adapter configurations and inbound-only adapters
- **EmergencyManager**: Handles emergency pause functionality
- **BridgeMessageCoordinator**: Coordinates bridge and rollback message operations
- **PredepositCoordinator**: Manages predeposit functionality for L1
- **IWhitelabeledUnit**: Interface for whitelabeled unit tokens that wrap underlying generic units with 1:1 parity

### Contract Surface
- `genericUnit (address)`: The address of the generic unit token that this coordinator manages
- `bridgeTypes (mapping)`: Complex nested mapping structure storing bridge configurations
- `failedMessageExecutions (mapping)`: Tracks failed message executions for rollback
- Inherits from `AccessControlUpgradeable` and `ReentrancyGuardTransientUpgradeable` for role-based access control and reentrancy protection

### Data Structures
#### LocalConfig
- `adapter`: The local bridge adapter contract instance
- `isInboundOnly`: Mapping of adapter addresses allowed only for inbound messages

#### RemoteConfig
- `adapter`: The remote bridge adapter address encoded as bytes32
- `isInboundOnly`: Mapping of remote adapter identifiers allowed only for inbound messages

#### BridgeTypeConfig
- `local`: The local bridge adapter configuration
- `remote`: Mapping of chain IDs to their remote bridge adapter configurations

#### PredepositChain (L1 only)
- `state`: The current state of predeposits for this chain (DISABLED, ENABLED, DISPATCHED, WITHDRAWN)
- `chainId`: The chain ID of the destination chain
- `predeposits`: Mapping of sender addresses to remote recipient addresses to predeposit amounts
- `totalPredeposits`: The total amount of units predeposited for this chain

#### Message Types
- `Message`: Contains `messageType` (enum) and `data` (bytes payload)
- `BridgeMessage`: Contains `omnichainSender`, `omnichainRecipient`, and `amount`

#### Whitelabeled Unit Interface
The `IWhitelabeledUnit` interface defines functionality for tokens that wrap underlying generic units:

##### Events
- `Wrapped(address indexed owner, uint256 amount)`: Emitted when underlying unit tokens are wrapped into whitelabeled tokens
- `Unwrapped(address indexed owner, address indexed recipient, uint256 amount)`: Emitted when whitelabeled tokens are unwrapped back to underlying unit tokens

##### Functions
- `wrap(address owner, uint256 amount) external`: Wraps underlying unit tokens into whitelabeled tokens with 1:1 parity
- `unwrap(address owner, address recipient, uint256 amount) external`: Unwraps whitelabeled tokens back to underlying unit tokens
- `genericUnit() external view returns (address)`: Returns the address of the underlying generic unit token

### Custom Errors
#### BridgeCoordinator Errors
- `ZeroGenericUnit()`: Thrown when generic unit token address is zero during initialization
- `ZeroAdmin()`: Thrown when admin address is zero during initialization
- `NoLocalBridgeAdapter()`: Thrown when no local bridge adapter is configured for the specified bridge type
- `NoRemoteBridgeAdapter()`: Thrown when no remote bridge adapter is configured for the bridge type and chain ID
- `OnlyLocalAdapter()`: Thrown when caller is not the expected local bridge adapter
- `OnlyRemoteAdapter()`: Thrown when remote sender is not the expected remote bridge adapter
- `CallerNotSelf()`: Thrown when tryReleaseTokens is called by an external address
- `UnsupportedMessageType(uint8 messageType)`: Thrown when an unsupported message type is encountered during inbound settlement

#### L1 Coordinator Errors
- `IncorrectEscrowBalance()`: Thrown when the amount of unit tokens restricted does not match the expected amount

#### AdapterManager Errors
- `CoordinatorMismatch()`: Thrown when bridge adapter's coordinator doesn't match this contract
- `BridgeTypeMismatch()`: Thrown when bridge adapter's type doesn't match the expected type
- `IsOutboundAdapter()`: Thrown when attempting to mark outbound adapter as inbound-only
- `IsNotAdapter()`: Thrown when attempting to swap an adapter that is not in the inbound-only list

#### BridgeMessage Errors
- `BridgeMessage_InvalidOnBehalf()`: Thrown when the onBehalf parameter is zero
- `BridgeMessage_InvalidRecipient()`: Thrown when the decoded recipient address is zero
- `BridgeMessage_InvalidRemoteRecipient()`: Thrown when the remote recipient parameter is zero
- `BridgeMessage_InvalidAmount()`: Thrown when the bridge amount is zero
- `BridgeMessage_NoFailedMessageExecution()`: Thrown when there is no recorded failed message execution for a given message ID
- `BridgeMessage_InvalidFailedMessageData()`: Thrown when the rollback message data does not match a failed message
- `BridgeMessage_InvalidMessageType()`: Thrown when the original message is not of type BRIDGE
- `BridgeMessage_NoSenderToRollback()`: Thrown when there is no sender address to rollback to

#### Predeposit Errors (L1 only)
- `Predeposit_NotEnabled()`: Thrown when predeposits are not enabled for the specified chain nickname
- `Predeposit_DispatchNotEnabled()`: Thrown when dispatching predeposits is not enabled
- `Predeposit_WithdrawalsNotEnabled()`: Thrown when withdrawals are not enabled
- `Predeposit_ChainIdAlreadySet()`: Thrown when the chain ID is already set
- `Predeposit_ZeroOnBehalf()`: Thrown when the onBehalf parameter is zero
- `Predeposit_ZeroRemoteRecipient()`: Thrown when the remote recipient parameter is zero
- `Predeposit_ZeroRecipient()`: Thrown when the recipient address is zero
- `Predeposit_ZeroAmount()`: Thrown when the bridge amount is zero
- `Predeposit_InvalidStateTransition()`: Thrown when the predeposit state transition is invalid
- `Predeposit_ChainIdZero()`: Thrown when the chain ID is zero

### Events
#### Core Bridge Events
- `MessageOut(uint16 bridgeType, uint256 destChainId, bytes32 messageId, bytes messageData)`: Emitted when a cross-chain message is dispatched
- `MessageIn(uint16 bridgeType, uint256 srcChainId, bytes32 messageId, bytes messageData)`: Emitted when a cross-chain message is received
- `MessageExecutionFailed(bytes32 messageId)`: Emitted when execution of an inbound message fails
- `BridgedOut(address sender, address indexed owner, bytes32 indexed remoteRecipient, uint256 amount, bytes32 indexed messageId, BridgeMessage messageData)`: Emitted when units are bridged out to another chain
- `BridgedIn(bytes32 indexed remoteSender, address indexed recipient, uint256 amount, bytes32 indexed messageId, BridgeMessage messageData)`: Emitted when units are bridged in from another chain
- `BridgeRollbackedOut(bytes32 rollbackedMessageId, bytes32 messageId)`: Emitted when a rollback bridge operation is initiated

#### Adapter Management Events
- `LocalInboundOnlyBridgeAdapterUpdated(uint16 bridgeType, address adapter, bool isInboundOnly)`: Emitted when a local bridge adapter's inbound-only status is updated
- `RemoteInboundOnlyBridgeAdapterUpdated(uint16 bridgeType, uint256 chainId, bytes32 adapter, bool isInboundOnly)`: Emitted when a remote bridge adapter's inbound-only status is updated
- `LocalOutboundBridgeAdapterUpdated(uint16 bridgeType, address adapter)`: Emitted when the outbound local bridge adapter is updated
- `RemoteOutboundBridgeAdapterUpdated(uint16 bridgeType, uint256 chainId, bytes32 adapter)`: Emitted when the outbound remote bridge adapter is updated

#### Predeposit Events (L1 only)
- `Predeposited(bytes32 indexed chainNickname, address sender, address indexed owner, bytes32 indexed remoteRecipient, uint256 amount)`: Emitted when users predeposit tokens for future bridging
- `PredepositBridgedOut(bytes32 chainNickname, bytes32 messageId)`: Emitted when a predeposit has been successfully bridged out
- `PredepositWithdrawn(bytes32 indexed chainNickname, address indexed owner, bytes32 indexed remoteRecipient, address recipient, uint256 amount)`: Emitted when a predeposit has been withdrawn back by the original owner
- `PredepositStateChanged(bytes32 chainNickname, PredepositState newState)`: Emitted when the predeposit state for a chain nickname changes
- `ChainIdAssignedToNickname(bytes32 chainNickname, uint256 chainId)`: Emitted when a chain ID is assigned to a chain nickname
- `WhitelabelAssignedToNickname(bytes32 indexed chainNickname, bytes32 indexed whitelabel)`: Emitted when a whitelabeled unit address is assigned to a nickname for a specific chain

## 3. Function Specifications

### Core BridgeCoordinator Functions
#### Initialization
- `constructor()`
  - Disables initializers for the implementation contract to prevent direct initialization
- `initialize(address _genericUnit, address _admin) external initializer`
  - Initializes the coordinator with generic unit token and admin addresses. Both must be non-zero
  - Sets the generic unit token address and grants `DEFAULT_ADMIN_ROLE` to the specified admin

#### Message Coordination
- `settleInboundMessage(uint16 bridgeType, uint256 chainId, bytes32 remoteSender, bytes calldata messageData, bytes32 messageId) external nonReentrant`
  - Called by bridge adapters (either current or inbound-only) when receiving cross-chain messages
  - Validates that both the calling adapter and remote sender are authorized for the bridge type and chain
  - Emits `MessageIn` and attempts to execute the message via `trySettleInboundMessage`
  - If execution fails, stores the failed message hash and emits `MessageExecutionFailed`
- `trySettleInboundMessage(bytes calldata messageData, bytes32 messageId) external`
  - Internal execution wrapper that can only be called by the contract itself
  - Decodes the message type and routes to appropriate handler (currently only BRIDGE messages)
- `_dispatchMessage(uint16 bridgeType, uint256 chainId, bytes memory messageData, bytes calldata bridgeParams) internal returns (bytes32 messageId)`
  - Internal function to dispatch cross-chain messages via bridge adapters
  - Validates that both local and remote adapters are configured
  - Calls the bridge adapter with the provided parameters and emits `MessageOut`

#### Token Management (Virtual Functions)
- `_restrictUnits(address whitelabel, address owner, uint256 amount) internal virtual`
  - Virtual function for unit restriction during outbound bridging
  - Takes a whitelabel parameter for supporting whitelabeled unit tokens (zero address for native units)
  - L1 implementation: transfers units from owner to coordinator using `safeTransferFrom`
  - L2 implementation: burns units from owner using `IERC20Mintable.burn`
- `_releaseUnits(address whitelabel, address receiver, uint256 amount) internal virtual`
  - Virtual function for unit release during inbound bridging
  - Takes a whitelabel parameter for supporting whitelabeled unit tokens (zero address for native units)
  - L1 implementation: transfers units from coordinator to receiver using `safeTransfer`
  - L2 implementation: mints units to receiver using `IERC20Mintable.mint`

### BridgeMessageCoordinator Functions
#### Bridge Operations
- `bridge(uint16 bridgeType, uint256 chainId, address onBehalf, bytes32 remoteRecipient, address sourceWhitelabel, bytes32 destinationWhitelabel, uint256 amount, bytes calldata bridgeParams) external payable nonReentrant returns (bytes32 messageId)`
  - Preconditions: `onBehalf != address(0)`, `amount > 0`, `remoteRecipient != bytes32(0)`, local and remote adapters must be configured
  - Supports whitelabeled units through sourceWhitelabel and destinationWhitelabel parameters
  - Restricts units via `_restrictUnits`, encodes bridge message, and dispatches via `_dispatchMessage`
  - Emits `BridgedOut` event with sender, owner, recipient, amount, and message ID
- `rollback(uint16 bridgeType, uint256 originalChainId, bytes calldata originalMessageData, bytes32 originalMessageId, bytes calldata bridgeParams) external payable nonReentrant returns (bytes32 rollbackMessageId)`
  - Validates failed message execution exists and matches provided data
  - Extracts original sender from failed message and creates rollback message
  - Dispatches rollback message to original chain and emits both `BridgedOut` and `BridgeRollbackedOut`

#### Message Processing
- `_settleInboundBridgeMessage(bytes memory messageData, bytes32 messageId) internal`
  - Decodes bridge message data and validates recipient and amount
  - Releases units via `_releaseUnits` and emits `BridgedIn` event
- `encodeBridgeMessage(bytes32 remoteSender, bytes32 remoteRecipient, uint256 amount) public pure returns (bytes memory)`
  - Utility function to encode BRIDGE type messages with sender, recipient, and amount data

### AdapterManager Functions
#### Inbound-Only Configuration
- `setIsInboundOnlyLocalBridgeAdapter(uint16 bridgeType, IBridgeAdapter adapter, bool isInboundOnly) external onlyRole(ADAPTER_MANAGER_ROLE)`
  - Manages inbound-only status for local bridge adapters
  - Validates adapter configuration when marking as inbound-only
- `setIsInboundOnlyRemoteBridgeAdapter(uint16 bridgeType, uint256 chainId, bytes32 adapter, bool isInboundOnly) external onlyRole(ADAPTER_MANAGER_ROLE)`
  - Manages inbound-only status for remote bridge adapters

#### Outbound Adapter Swapping
- `swapOutboundLocalBridgeAdapter(uint16 bridgeType, IBridgeAdapter adapter) external onlyRole(ADAPTER_MANAGER_ROLE)`
  - Swaps an existing inbound-only adapter to become the outbound adapter
  - Previous outbound adapter is marked as inbound-only to maintain continuity
- `swapOutboundRemoteBridgeAdapter(uint16 bridgeType, uint256 chainId, bytes32 adapter) external onlyRole(ADAPTER_MANAGER_ROLE)`
  - Swaps an existing inbound-only adapter to become the outbound adapter
  - Previous outbound adapter is marked as inbound-only to maintain continuity

### PredepositCoordinator Functions (L1 Only)
#### Predeposit Lifecycle
- `predeposit(bytes32 chainNickname, address onBehalf, bytes32 remoteRecipient, uint256 amount) external nonReentrant`
  - Allows users to predeposit units for future bridging when chain is in ENABLED state
  - Includes onBehalf parameter to specify the owner of the predeposit
  - Restricts units immediately and tracks predeposit amount per owner/recipient pair
- `bridgePredeposit(uint16 bridgeType, bytes32 chainNickname, address onBehalf, bytes32 remoteRecipient, bytes calldata bridgeParams) external payable nonReentrant returns (bytes32 messageId)`
  - Bridges predeposited units when chain is in DISPATCHED state
  - Deletes predeposit record and dispatches bridge message
- `withdrawPredeposit(bytes32 chainNickname, address onBehalf, bytes32 remoteRecipient, address recipient) external nonReentrant`
  - Allows withdrawal of predeposited units when chain is in WITHDRAWN state
  - Releases units back to specified recipient address

#### State Management
- `enablePredeposits(bytes32 chainNickname) external onlyRole(PREDEPOSIT_MANAGER_ROLE)`
  - Transitions chain from DISABLED to ENABLED state
- `enablePredepositsDispatch(bytes32 chainNickname, uint256 chainId) external onlyRole(PREDEPOSIT_MANAGER_ROLE)`
  - Transitions chain from ENABLED to DISPATCHED state and assigns chain ID
- `enablePredepositsWithdraw(bytes32 chainNickname) external onlyRole(PREDEPOSIT_MANAGER_ROLE)`
  - Transitions chain from ENABLED to WITHDRAWN state
- `setChainIdToNickname(bytes32 chainNickname, uint256 chainId) external onlyRole(PREDEPOSIT_MANAGER_ROLE)`
  - Updates chain ID for nickname when in DISPATCHED state

### View Functions
- `supportsBridgeTypeFor(uint16 bridgeType, uint256 chainId) external view returns (bool)`
  - Returns true if both local and remote adapters are configured for the bridge type and chain
- `localBridgeAdapter(uint16 bridgeType) external view returns (IBridgeAdapter)`
  - Returns the local bridge adapter for a specific bridge type
- `remoteBridgeAdapter(uint16 bridgeType, uint256 chainId) external view returns (bytes32)`
  - Returns the remote bridge adapter address for a specific bridge type and chain
- `isInboundOnlyLocalBridgeAdapter(uint16 bridgeType, address adapter) external view returns (bool)`
  - Checks if a local adapter is marked as inbound-only
- `isInboundOnlyRemoteBridgeAdapter(uint16 bridgeType, uint256 chainId, bytes32 adapter) external view returns (bool)`
  - Checks if a remote adapter is marked as inbound-only
- `encodeOmnichainAddress(address addr) public pure returns (bytes32)`
  - Utility function to encode an EVM address to bytes32 for cross-chain compatibility
- `decodeOmnichainAddress(bytes32 oAddr) public pure returns (address)`
  - Utility function to decode a bytes32 value back to an EVM address
- `getChainPredepositState(bytes32 chainNickname) external view returns (PredepositState)` (L1 only)
  - Gets the predeposit state for the specified chain nickname
- `getChainIdForNickname(bytes32 chainNickname) external view returns (uint256)` (L1 only)
  - Gets the chain ID assigned to the specified chain nickname
- `getPredeposit(bytes32 chainNickname, address onBehalf, bytes32 remoteRecipient) external view returns (uint256)` (L1 only)
  - Gets the predeposited amount for a given onBehalf address and remote recipient
- `getTotalPredeposits(bytes32 chainNickname) external view returns (uint256)` (L1 only)
  - Gets the total amount of units predeposited for the specified chain nickname

## 4. Behavioural Notes
- All adapter calls are non-reentrant because the hub inherits `ReentrancyGuard`.
- Share token balances held by the coordinator must always match the sum of outstanding cross-chain liabilities; adapters must emit/propagate `messageId` for reconciliation.
- Governance actions (chain support, adapter overrides) should be executed through the project’s timelock to retain on-chain auditability.
- Bridge fee accounting uses `msg.value`; the coordinator forwards the full amount to the adapter and does not rebate excess ETH. Callers are expected to supply the adapter’s quoted fee exactly.

## 5. Integration Checklist
- Bridge adapters MUST implement the `IBridgeAdapter` interface with `bridge()`, `estimateBridgeFee()`, `bridgeType()`, and `bridgeCoordinator()` functions.
- Adapters MUST accept calls only from their designated coordinator and forward cross-chain messages only to/from other coordinators to maintain the trust boundary.
- Adapters must be configured on both local and remote chains with matching bridge types.
- For L2 deployments, use `BridgeCoordinatorL2` which overrides token handling to burn/mint instead of transfer.
- Generic unit tokens must implement `IERC20Mintable` interface for L2 coordinator burn/mint operations.
- Whitelabeled units must implement `IWhitelabeledUnit` interface for wrapping/unwrapping functionality on L1.
- Monitoring should track `BridgedOut` and `BridgedIn` events to ensure proper cross-chain token accounting.
- Governance should manage adapter configurations through the owner role, preferably via timelock for security.
