# Generic Bridging

A modular, bridging infrastructure for secure cross-chain token transfers with support for multiple bridge protocols and proper supply management.

## Overview

Generic Bridging provides a unified framework for coordinating cross-chain token transfers through multiple bridge protocols. The system maintains proper token supply consistency across chains while supporting various bridging mechanisms including LayerZero and Linea Bridge.

### Key Features

- **Modular Bridge Architecture**: Pluggable adapter system supporting multiple bridge protocols
- **Supply Consistency**: L1 uses token locking/unlocking, L2s use mint/burn for proper supply management
- **Multi-Protocol Support**: Built-in adapters for LayerZero and Linea Bridge with extensible interface
- **Emergency Controls**: Circuit breakers and pause functionality for security
- **Predeposit System**: L1 predeposit functionality for early chain deployments
- **Failed Message Handling**: Comprehensive rollback mechanisms for failed cross-chain operations

## Architecture

### Core Components

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│ BridgeCoordinator│    │  Bridge Adapters │    │   Share Token    │
│                  │    │                  │    │                  │
│ • Message Route  │◄──►│ • LayerZero      │◄──►│ • ERC20 Token    │
│ • Token Mgmt     │    │ • Linea Bridge   │    │ • L1: Lock/Unlock│
│ • Emergency Ctrl │    │ • Custom Bridges │    │ • L2: Mint/Burn  │
│ • Predeposits    │    │                  │    │                  │
│ • Rollbacks      │    │                  │    │                  │
└──────────────────┘    └──────────────────┘    └──────────────────┘
```

### Module Structure

- **`src/coordinator/`**: Bridge coordination logic (`BridgeCoordinator`, `AdapterManager`, `EmergencyManager`)
- **`src/adapters/`**: Bridge protocol adapters (`LayerZeroAdapter`, `LineaBridgeAdapter`, `BaseAdapter`)
- **`src/interfaces/`**: Core interfaces (`IBridgeCoordinator`, `IBridgeAdapter`, `IERC20Mintable`)
- **`BridgeCoordinatorL1.sol`**: L1-specific coordinator with predeposit functionality
- **`BridgeCoordinatorL2.sol`**: L2-specific coordinator with mint/burn token management

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/MetaFi-Labs/generic-bridging.git
cd generic-bridging
```

2. Initialize submodules:
```bash
git submodule update --init --recursive
```

3. Install dependencies:
```bash
forge install
```

### Build

Compile the contracts:
```bash
forge build
```

### Testing

Run the full test suite:
```bash
forge test
```

Run with gas reporting:
```bash
forge test --gas-report
```

Run with fork testing (requires `ETH_RPC_URL`):
```bash
forge test --fork-url $ETH_RPC_URL
```

Generate coverage report:
```bash
forge coverage
```

## Bridge Design

### Core Principles

The bridging system maintains these core principles:

- **Supply Consistency**: Token supply is properly managed across chains (L1 locks/unlocks, L2s mint/burn)
- **Protocol Agnostic**: Modular adapter architecture supports multiple bridge protocols
- **Security First**: Emergency controls and circuit breakers for operational safety

### Bridge Coordinators

The system uses specialized coordinators for different chain types:

- **BridgeCoordinatorL1**: Handles token locking/unlocking and predeposit functionality on Layer 1
- **BridgeCoordinatorL2**: Manages token minting/burning on Layer 2 chains for proper supply control
- **Base Architecture**: Shared components including adapter management and emergency controls

### Bridge Adapters

Each bridge protocol has a dedicated adapter:

- **LayerZeroAdapter**: Integration with LayerZero's omnichain infrastructure using OApp framework
- **LineaBridgeAdapter**: Integration with Linea's native bridge protocol
- **BaseAdapter**: Common adapter interface and functionality for consistent integration patterns

### Message Flow

1. **Outbound**: User initiates bridge → Coordinator restricts tokens → Adapter dispatches message
2. **Inbound**: Adapter receives message → Coordinator validates → Tokens released/minted to recipient
3. **Rollback**: Failed messages can be rolled back through dedicated rollback mechanisms

## Testing Strategy

### Test Categories

- **Unit Tests**: Individual contract functionality (`tests/unit/`)
- **Integration Tests**: Cross-contract interactions (`tests/integration/`)
- **Harness Tests**: Test harnesses for complex scenarios (`tests/harness/`)

### Key Test Areas

- Cross-chain message handling and validation
- Token supply consistency across chains
- Bridge adapter integration and failure scenarios
- Emergency pause and rollback functionality
- Predeposit system mechanics on L1

## Documentation

- **Contract Specifications**: [`specs/contracts/`](specs/contracts/)

## License

This project is licensed under the Business Source License 1.1 (BUSL-1.1).

## Links

- **Repository**: [github.com/MetaFi-Labs/generic-bridging](https://github.com/MetaFi-Labs/generic-bridging)
- **Generic Protocol**: [github.com/MetaFi-Labs/generic-protocol](https://github.com/MetaFi-Labs/generic-protocol)

---

*Built with ❤️ by the MetaFi Labs team*
