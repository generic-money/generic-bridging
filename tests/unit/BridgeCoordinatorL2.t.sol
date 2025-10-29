// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { IBridgeAdapter } from "../../src/coordinator/BridgeCoordinator.sol";
import { IERC20Mintable } from "../../src/BridgeCoordinatorL2.sol";
import { BridgeMessage } from "../../src/coordinator/Message.sol";

import { BridgeCoordinatorL2Harness } from "../harness/BridgeCoordinatorL2Harness.sol";

abstract contract BridgeCoordinatorL2Test is Test {
    BridgeCoordinatorL2Harness coordinator;

    address share = makeAddr("share");
    address admin = makeAddr("admin");
    address manager = makeAddr("manager");
    bytes32 managerRole;
    address sender = makeAddr("sender");
    address owner = makeAddr("owner");
    bytes32 remoteSender = bytes32(uint256(uint160(makeAddr("remoteSender"))));
    address recipient = makeAddr("recipient");
    bytes32 remoteRecipient = bytes32(uint256(uint160(makeAddr("remoteRecipient"))));
    address srcWhitelabel = address(0);
    bytes32 destWhitelabel = bytes32(0);
    bytes32 messageId = keccak256("messageId");

    uint16 bridgeType = 7;
    uint256 remoteChainId = 42;
    address localAdapter = makeAddr("localAdapter");
    bytes32 remoteAdapter = bytes32(uint256(uint160(makeAddr("remoteAdapter"))));

    function _resetInitializableStorageSlot() internal {
        // reset the Initializable storage slot to allow usage of deployed instance in tests
        vm.store(address(coordinator), coordinator.exposed_initializableStorageSlot(), bytes32(0));
    }

    function setUp() public virtual {
        coordinator = new BridgeCoordinatorL2Harness();
        _resetInitializableStorageSlot();
        coordinator.initialize(share, admin);

        managerRole = coordinator.ADAPTER_MANAGER_ROLE();
        vm.prank(admin);
        coordinator.grantRole(managerRole, manager);

        vm.mockCall(
            localAdapter,
            abi.encodeWithSelector(IBridgeAdapter.bridgeCoordinator.selector),
            abi.encode(address(coordinator))
        );
        vm.mockCall(localAdapter, abi.encodeWithSelector(IBridgeAdapter.bridgeType.selector), abi.encode(bridgeType));
        vm.mockCall(localAdapter, abi.encodeWithSelector(IBridgeAdapter.estimateBridgeFee.selector), abi.encode(0));
        vm.mockCall(localAdapter, abi.encodeWithSelector(IBridgeAdapter.bridge.selector), abi.encode(messageId));

        vm.mockCall(share, abi.encodeWithSelector(IERC20Mintable.mint.selector), "");
        vm.mockCall(share, abi.encodeWithSelector(IERC20Mintable.burn.selector), "");

        coordinator.workaround_setOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter);
    }
}

contract BridgeCoordinatorL2_Bridge_Test is BridgeCoordinatorL2Test {
    function testFuzz_shouldBurnTokensFromSender(uint256 amount) public {
        vm.assume(amount > 0);

        vm.expectCall(share, abi.encodeWithSelector(IERC20Mintable.burn.selector, sender, address(coordinator), amount));

        vm.prank(sender);
        coordinator.bridge(bridgeType, remoteChainId, owner, remoteRecipient, srcWhitelabel, destWhitelabel, amount, "");
    }
}

contract BridgeCoordinatorL2_SettleInboundBridge_Test is BridgeCoordinatorL2Test {
    function testFuzz_shouldMintTokens(address _recipient, uint256 amount) public {
        vm.assume(_recipient != address(0));
        vm.assume(amount > 0);

        bytes memory messageData = coordinator.encodeBridgeMessage(
            BridgeMessage({
                sender: remoteSender,
                recipient: coordinator.encodeOmnichainAddress(_recipient),
                sourceWhitelabel: coordinator.encodeOmnichainAddress(srcWhitelabel),
                destinationWhitelabel: destWhitelabel,
                amount: amount
            })
        );

        vm.expectCall(share, abi.encodeWithSelector(IERC20Mintable.mint.selector, _recipient, amount));

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);
    }
}
