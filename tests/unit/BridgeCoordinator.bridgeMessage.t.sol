// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {
    BridgeCoordinator,
    BaseBridgeCoordinator,
    BridgeMessageCoordinator,
    IBridgeAdapter,
    IERC20
} from "../../src/coordinator/BridgeCoordinator.sol";

import { BridgeCoordinatorTest, BridgeCoordinator_SettleInboundBridge_Test } from "./BridgeCoordinator.t.sol";

abstract contract BridgeCoordinator_BridgeMessage_Test is BridgeCoordinatorTest { }

contract BridgeCoordinator_BridgeMessage_Bridge_Test is BridgeCoordinator_BridgeMessage_Test {
    function test_shouldRevert_whenNoLocalAdapter() public {
        coordinator.workaround_setOutboundLocalBridgeAdapter(bridgeType, address(0)); // remove local adapter

        vm.expectRevert(BridgeCoordinator.NoLocalBridgeAdapter.selector);
        coordinator.bridge(bridgeType, remoteChainId, remoteRecipient, 1, "");
    }

    function test_shouldRevert_whenNoRemoteAdapter() public {
        // remove remote adapter
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, bytes32(0));

        vm.expectRevert(BridgeCoordinator.NoRemoteBridgeAdapter.selector);
        coordinator.bridge(bridgeType, remoteChainId, remoteRecipient, 1, "");
    }

    function test_shouldRevert_whenOnlyInboundLocalAdapter() public {
        coordinator.workaround_setOutboundLocalBridgeAdapter(bridgeType, address(0)); // remove local adapter
        coordinator.workaround_setIsInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter, true);

        vm.expectRevert(BridgeCoordinator.NoLocalBridgeAdapter.selector);
        coordinator.bridge(bridgeType, remoteChainId, remoteRecipient, 1, "");
    }

    function test_shouldRevert_whenOnlyInboundRemoteAdapter() public {
        // remove remote adapter
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, bytes32(0));
        coordinator.workaround_setIsInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter, true);

        vm.expectRevert(BridgeCoordinator.NoRemoteBridgeAdapter.selector);
        coordinator.bridge(bridgeType, remoteChainId, remoteRecipient, 1, "");
    }

    function test_shouldRevert_whenRemoteRecipientIsZero() public {
        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidRemoteRecipient.selector);
        coordinator.bridge(bridgeType, remoteChainId, bytes32(0), 1, "");
    }

    function test_shouldRevert_whenAmountIsZero() public {
        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidAmount.selector);
        coordinator.bridge(bridgeType, remoteChainId, remoteRecipient, 0, "");
    }

    function testFuzz_shouldCallBridgeOnLocalAdapter(
        uint256 fee,
        uint256 amount,
        bytes calldata bridgeParams
    )
        public
    {
        vm.assume(amount > 0);
        fee = bound(fee, 1 ether, 10 ether);

        deal(sender, fee);

        bytes memory bridgeMessageData =
            coordinator.encodeBridgeMessage(coordinator.encodeOmnichainAddress(sender), remoteRecipient, amount);

        vm.expectCall(
            localAdapter,
            fee,
            abi.encodeWithSelector(
                IBridgeAdapter.bridge.selector,
                remoteChainId,
                remoteAdapter,
                bridgeMessageData,
                sender, // caller as refund address
                bridgeParams
            )
        );

        vm.prank(sender);
        coordinator.bridge{ value: fee }(bridgeType, remoteChainId, remoteRecipient, amount, bridgeParams);
    }

    function testFuzz_shouldLockTokens(uint256 amount) public {
        vm.assume(amount > 0);

        vm.expectCall(share, abi.encodeWithSelector(IERC20.transferFrom.selector, sender, address(coordinator), amount));

        vm.prank(sender);
        coordinator.bridge(bridgeType, remoteChainId, remoteRecipient, amount, "");
    }

    function test_shouldReturnMessageId() public {
        bytes32 returnedMessageId = coordinator.bridge(bridgeType, remoteChainId, remoteRecipient, 1, "");

        assertEq(returnedMessageId, messageId);
    }

    function test_shouldEmit_MessageOut() public {
        bytes memory bridgeMessageData =
            coordinator.encodeBridgeMessage(coordinator.encodeOmnichainAddress(sender), remoteRecipient, 1);

        vm.expectEmit();
        emit BridgeCoordinator.MessageOut(bridgeType, remoteChainId, messageId, bridgeMessageData);

        vm.prank(sender);
        coordinator.bridge(bridgeType, remoteChainId, remoteRecipient, 1, "");
    }

    function testFuzz_shouldEmit_BridgedOut(uint256 amount) public {
        vm.assume(amount > 0);

        vm.expectEmit();
        emit BridgeMessageCoordinator.BridgedOut(sender, remoteRecipient, amount, messageId);

        vm.prank(sender);
        coordinator.bridge(bridgeType, remoteChainId, remoteRecipient, amount, "");
    }
}

contract BridgeCoordinator_BridgeMessage_Rollback_Test is BridgeCoordinator_BridgeMessage_Test {
    bytes32 originalRemoteSender = keccak256("originalRemoteSender");
    bytes32 originalOmnichainRecipient = keccak256("originalOmnichainRecipient");
    uint256 originalAmount = 1000 ether;
    bytes32 originalMessageId = keccak256("originalMessageId");
    bytes32 failedMessagesHash;
    bytes originalMessageData;

    function setUp() public override {
        super.setUp();

        originalMessageData =
            coordinator.encodeBridgeMessage(originalRemoteSender, originalOmnichainRecipient, originalAmount);
        failedMessagesHash = keccak256(abi.encode(remoteChainId, originalMessageData));
        coordinator.workaround_setFailedMessageExecution(originalMessageId, failedMessagesHash);
    }

    function test_shouldRevert_whenNoLocalAdapter() public {
        coordinator.workaround_setOutboundLocalBridgeAdapter(bridgeType, address(0)); // remove local adapter

        vm.expectRevert(BridgeCoordinator.NoLocalBridgeAdapter.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldRevert_whenNoRemoteAdapter() public {
        // remove remote adapter
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, bytes32(0));

        vm.expectRevert(BridgeCoordinator.NoRemoteBridgeAdapter.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldRevert_whenOnlyInboundLocalAdapter() public {
        coordinator.workaround_setOutboundLocalBridgeAdapter(bridgeType, address(0)); // remove local adapter
        coordinator.workaround_setIsInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter, true);

        vm.expectRevert(BridgeCoordinator.NoLocalBridgeAdapter.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldRevert_whenOnlyInboundRemoteAdapter() public {
        // remove remote adapter
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, bytes32(0));
        coordinator.workaround_setIsInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter, true);

        vm.expectRevert(BridgeCoordinator.NoRemoteBridgeAdapter.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldRevert_whenNoFailedMessageExecution() public {
        bytes32 badMessageId = keccak256("badMessageId");

        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_NoFailedMessageExecution.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, badMessageId, "");
    }

    function test_shouldRevert_whenIncorrectFailedMessageData() public {
        // Register remote adapter for different chain ID so that the rollback does not revert on missing adapter
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId + 1, remoteAdapter);

        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidFailedMessageData.selector);
        coordinator.rollback(bridgeType, remoteChainId + 1, originalMessageData, originalMessageId, "");

        originalMessageData =
            coordinator.encodeBridgeMessage(originalRemoteSender << 1, originalOmnichainRecipient, originalAmount);
        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidFailedMessageData.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldDeleteFailedMessageHash() public {
        assertEq(coordinator.failedMessageExecutions(originalMessageId), failedMessagesHash);

        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");

        assertEq(coordinator.failedMessageExecutions(originalMessageId), bytes32(0));
    }

    function test_shouldRevert_whenFailedMessageNotBridgeType() public {
        // Note: skipping this test as any attempt to encode a message value out of enum scope panics
        // stop skipping after adding new message type
        vm.skip(true);

        // Encode original message as a rollback message instead of bridge message
        originalMessageData = abi.encode(
            uint8(99),
            BaseBridgeCoordinator.BridgeMessage({
                omnichainSender: originalRemoteSender,
                omnichainRecipient: originalOmnichainRecipient,
                amount: originalAmount
            })
        );
        failedMessagesHash = keccak256(abi.encode(remoteChainId, originalMessageData));
        coordinator.workaround_setFailedMessageExecution(originalMessageId, failedMessagesHash);

        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidMessageType.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function testFuzz_shouldBridgeRollbackMessage(
        bytes32 msgId,
        address sender,
        uint256 amount,
        uint256 fee,
        bytes memory bridgeParams
    )
        public
    {
        vm.assume(msgId != bytes32(0));
        vm.assume(sender != address(0));
        fee = bound(fee, 0, 10 ether);

        address caller = makeAddr("caller");
        deal(caller, fee);

        originalMessageId = msgId;
        originalRemoteSender = coordinator.encodeOmnichainAddress(sender);
        originalAmount = amount; // can be 0

        originalMessageData = coordinator.encodeBridgeMessage(originalRemoteSender, remoteRecipient, originalAmount);
        failedMessagesHash = keccak256(abi.encode(remoteChainId, originalMessageData));
        coordinator.workaround_setFailedMessageExecution(originalMessageId, failedMessagesHash);

        bytes memory rollbackMessageData =
            coordinator.encodeBridgeMessage(bytes32(0), originalRemoteSender, originalAmount);

        vm.expectCall(
            localAdapter,
            fee,
            abi.encodeWithSelector(
                IBridgeAdapter.bridge.selector,
                remoteChainId,
                remoteAdapter,
                rollbackMessageData,
                caller, // caller as refund address
                bridgeParams
            )
        );

        vm.prank(caller);
        coordinator.rollback{ value: fee }(
            bridgeType, remoteChainId, originalMessageData, originalMessageId, bridgeParams
        );
    }

    function test_shouldEmit_MessageOut() public {
        bytes memory rollbackMessageData =
            coordinator.encodeBridgeMessage(bytes32(0), originalRemoteSender, originalAmount);

        vm.expectEmit();
        emit BridgeCoordinator.MessageOut(bridgeType, remoteChainId, messageId, rollbackMessageData);

        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldEmit_BridgeRollbackedOut() public {
        vm.expectEmit();
        emit BridgeMessageCoordinator.BridgeRollbackedOut(originalMessageId, messageId);

        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldEmit_BridgedOut() public {
        vm.expectEmit();
        emit BridgeMessageCoordinator.BridgedOut(address(0), originalRemoteSender, originalAmount, messageId);

        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldReturnMessageId() public {
        bytes32 returnedMessageId =
            coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");

        assertEq(returnedMessageId, messageId);
    }
}

contract BridgeCoordinator_SettleInboundBridge_BridgeMessage_Test is
    BridgeCoordinator_BridgeMessage_Test,
    BridgeCoordinator_SettleInboundBridge_Test
{
    function setUp() public override {
        super.setUp();

        messageData = coordinator.encodeBridgeMessage(remoteSender, bytes32(uint256(uint160(recipient))), 500);
    }

    function test_shouldStoreFailedMessage_whenRecipientIsZero() public {
        messageData = coordinator.encodeBridgeMessage(remoteSender, bytes32(0), 500);

        vm.expectEmit();
        emit BridgeCoordinator.MessageExecutionFailed(messageId);

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);

        bytes32 failedMessageHash = keccak256(abi.encode(remoteChainId, messageData));
        assertEq(coordinator.failedMessageExecutions(messageId), failedMessageHash);
    }

    function test_shouldStoreFailedMessage_whenAmountIsZero() public {
        messageData = coordinator.encodeBridgeMessage(remoteSender, remoteRecipient, 0);

        vm.expectEmit();
        emit BridgeCoordinator.MessageExecutionFailed(messageId);

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);

        bytes32 failedMessageHash = keccak256(abi.encode(remoteChainId, messageData));
        assertEq(coordinator.failedMessageExecutions(messageId), failedMessageHash);
    }

    function testFuzz_shouldUnlockTokens(address _recipient, uint256 amount) public {
        vm.assume(_recipient != address(0));
        vm.assume(amount > 0);

        messageData =
            coordinator.encodeBridgeMessage(remoteSender, coordinator.encodeOmnichainAddress(_recipient), amount);

        vm.expectCall(share, abi.encodeWithSelector(IERC20.transfer.selector, _recipient, amount));

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);
    }

    function test_shouldEmit_BridgedIn() public {
        vm.expectEmit();
        emit BridgeMessageCoordinator.BridgedIn(remoteSender, recipient, 500, messageId);

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);
    }
}
