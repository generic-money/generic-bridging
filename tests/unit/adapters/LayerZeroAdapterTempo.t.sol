// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Vm } from "forge-std/Vm.sol";

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { ExecutorOptions } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/libs/ExecutorOptions.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { LayerZeroAdapterTempo } from "../../../src/chains/tempo/LayerZeroAdapterTempo.sol";
import { LayerZeroAdapter } from "../../../src/adapters/LayerZeroAdapter.sol";
import { IBridgeCoordinator } from "../../../src/interfaces/IBridgeCoordinator.sol";
import { BridgeMessage, Message, MessageType } from "../../../src/coordinator/Message.sol";

import { BridgeCoordinatorHarness } from "../../harness/BridgeCoordinatorHarness.sol";
import { BaseBridgeCoordinatorHarness } from "../../harness/BaseBridgeCoordinatorHarness.sol";

contract LayerZeroAdapterTempoHarness is LayerZeroAdapterTempo {
    constructor(
        IBridgeCoordinator coordinator,
        address owner,
        address endpoint
    )
        LayerZeroAdapterTempo(coordinator, owner, endpoint)
    { }
}

contract LayerZeroAdapterHarness is LayerZeroAdapter {
    constructor(
        IBridgeCoordinator coordinator,
        address owner,
        address endpoint
    )
        LayerZeroAdapter(coordinator, owner, endpoint)
    { }
}

contract FailingBridgeCoordinatorHarness is BridgeCoordinatorHarness {
    error ForcedReleaseFailure();

    bool public failRelease;

    function setFailRelease(bool shouldFail) external {
        failRelease = shouldFail;
    }

    function _releaseUnits(address whitelabel, address receiver, uint256 amount) internal override {
        if (failRelease) {
            revert ForcedReleaseFailure();
        }

        super._releaseUnits(whitelabel, receiver, amount);
    }
}

contract LayerZeroAdapterTempoTest is TestHelperOz5 {
    using PacketV1Codec for bytes;

    uint256 internal constant CHAIN_ID_TEMPO = 4217;
    uint256 internal constant CHAIN_ID_REMOTE = 1;
    uint256 internal constant SCALE = 1e12;
    uint16 internal constant BRIDGE_TYPE = 1;
    uint16 internal constant EID_TEMPO = 1;
    uint16 internal constant EID_REMOTE = 2;
    uint8 internal constant EXECUTOR_WORKER_ID = 1;
    uint8 internal constant OPTION_TYPE_LZRECEIVE = 1;

    FailingBridgeCoordinatorHarness internal tempoCoordinator;
    BridgeCoordinatorHarness internal remoteCoordinator;
    LayerZeroAdapterTempoHarness internal tempoAdapter;
    LayerZeroAdapterHarness internal remoteAdapter;

    address internal owner = makeAddr("owner");
    address internal unitToken = makeAddr("unitToken");
    address internal tempoUser = makeAddr("tempoUser");
    address internal remoteUser = makeAddr("remoteUser");
    address internal refundAddress = makeAddr("refundAddress");
    bytes32 internal tempoAdapterId;
    bytes32 internal remoteAdapterId;

    function setUp() public override {
        super.setUp();

        setUpEndpoints(2, LibraryType.UltraLightNode);

        tempoCoordinator = new FailingBridgeCoordinatorHarness();
        remoteCoordinator = new BridgeCoordinatorHarness();
        _initializeCoordinator(tempoCoordinator);
        _initializeCoordinator(remoteCoordinator);

        tempoAdapter = new LayerZeroAdapterTempoHarness(tempoCoordinator, owner, endpoints[EID_TEMPO]);
        remoteAdapter = new LayerZeroAdapterHarness(remoteCoordinator, owner, endpoints[EID_REMOTE]);
        tempoAdapterId = bytes32(uint256(uint160(address(tempoAdapter))));
        remoteAdapterId = bytes32(uint256(uint160(address(remoteAdapter))));

        vm.startPrank(owner);
        tempoCoordinator.workaround_setIsLocalBridgeAdapter(BRIDGE_TYPE, address(tempoAdapter), true);
        tempoCoordinator.workaround_setOutboundLocalBridgeAdapter(BRIDGE_TYPE, address(tempoAdapter));
        tempoCoordinator.workaround_setIsRemoteBridgeAdapter(BRIDGE_TYPE, CHAIN_ID_REMOTE, remoteAdapterId, true);
        tempoCoordinator.workaround_setOutboundRemoteBridgeAdapter(BRIDGE_TYPE, CHAIN_ID_REMOTE, remoteAdapterId);
        tempoAdapter.setRemoteEndpointConfig(CHAIN_ID_REMOTE, EID_REMOTE, remoteAdapterId);

        remoteCoordinator.workaround_setIsLocalBridgeAdapter(BRIDGE_TYPE, address(remoteAdapter), true);
        remoteCoordinator.workaround_setOutboundLocalBridgeAdapter(BRIDGE_TYPE, address(remoteAdapter));
        remoteCoordinator.workaround_setIsRemoteBridgeAdapter(BRIDGE_TYPE, CHAIN_ID_TEMPO, tempoAdapterId, true);
        remoteCoordinator.workaround_setOutboundRemoteBridgeAdapter(BRIDGE_TYPE, CHAIN_ID_TEMPO, tempoAdapterId);
        remoteAdapter.setRemoteEndpointConfig(CHAIN_ID_TEMPO, EID_TEMPO, tempoAdapterId);
        vm.stopPrank();
    }

    function test_bridgeDispatchesCanonicalizedOutboundPacket() public {
        uint256 localAmount = 1_234_567;
        address remoteRecipientAddress = makeAddr("remoteRecipient");
        bytes32 remoteRecipient = tempoCoordinator.encodeOmnichainAddress(remoteRecipientAddress);
        bytes memory localMessage =
            _encodeBridgeMessage(tempoCoordinator, tempoUser, remoteRecipient, bytes32(0), bytes32(0), localAmount);
        bytes memory bridgeOptions = buildReceiveOptions(200_000);
        uint256 nativeFee = tempoAdapter.estimateBridgeFee(CHAIN_ID_REMOTE, localMessage, bridgeOptions);

        vm.deal(tempoUser, nativeFee);
        vm.prank(tempoUser);
        bytes32 sentMessageId = tempoCoordinator.bridge{ value: nativeFee }(
            BRIDGE_TYPE, CHAIN_ID_REMOTE, tempoUser, remoteRecipient, address(0), bytes32(0), localAmount, bridgeOptions
        );

        (,, uint256 restrictedAmount) = tempoCoordinator.lastRestrictCall();
        assertEq(restrictedAmount, localAmount, "tempo coordinator should restrict local amount");

        assertTrue(hasPendingPackets(EID_REMOTE, remoteAdapterId), "packet not queued");
        bytes memory packet = getNextInflightPacket(EID_REMOTE, remoteAdapterId);
        this.assertPacketBridgeAmount(packet, localAmount * SCALE, sentMessageId, remoteRecipient);
    }

    function test_lzReceiveFloorsCanonicalAmountToTempoLocalUnits() public {
        uint256 localAmount = 1_300_000;
        uint256 canonicalAmount = localAmount * SCALE + 321;
        bytes32 tempoRecipient = tempoCoordinator.encodeOmnichainAddress(makeAddr("tempoRecipient"));
        bytes memory remoteMessage = _encodeBridgeMessage(
            remoteCoordinator, remoteUser, tempoRecipient, bytes32(0), bytes32(0), canonicalAmount
        );
        bytes memory bridgeOptions = buildReceiveOptions(200_000);
        uint256 nativeFee = remoteAdapter.estimateBridgeFee(CHAIN_ID_TEMPO, remoteMessage, bridgeOptions);

        vm.deal(remoteUser, nativeFee);
        vm.prank(remoteUser);
        bytes32 messageId = remoteCoordinator.bridge{ value: nativeFee }(
            BRIDGE_TYPE,
            CHAIN_ID_TEMPO,
            remoteUser,
            tempoRecipient,
            address(0),
            bytes32(0),
            canonicalAmount,
            bridgeOptions
        );

        verifyPackets(EID_TEMPO, address(tempoAdapter));

        (, address recipient, uint256 releasedAmount) = tempoCoordinator.lastReleaseCall();
        assertEq(recipient, makeAddr("tempoRecipient"), "recipient mismatch");
        assertEq(releasedAmount, localAmount, "tempo inbound amount should floor to local units");
        assertEq(tempoCoordinator.failedMessageExecutions(messageId), bytes32(0), "unexpected failed message");
    }

    function test_lzReceiveDropsSubUnitDustWithoutRecordingFailure() public {
        uint256 canonicalAmount = SCALE - 1;
        bytes32 tempoRecipient = tempoCoordinator.encodeOmnichainAddress(makeAddr("tempoRecipient"));
        bytes memory remoteMessage = _encodeBridgeMessage(
            remoteCoordinator, remoteUser, tempoRecipient, bytes32(0), bytes32(0), canonicalAmount
        );
        bytes memory bridgeOptions = buildReceiveOptions(200_000);
        uint256 nativeFee = remoteAdapter.estimateBridgeFee(CHAIN_ID_TEMPO, remoteMessage, bridgeOptions);

        vm.deal(remoteUser, nativeFee);
        vm.prank(remoteUser);
        bytes32 messageId = remoteCoordinator.bridge{ value: nativeFee }(
            BRIDGE_TYPE,
            CHAIN_ID_TEMPO,
            remoteUser,
            tempoRecipient,
            address(0),
            bytes32(0),
            canonicalAmount,
            bridgeOptions
        );

        verifyPackets(EID_TEMPO, address(tempoAdapter));

        (, address recipient, uint256 releasedAmount) = tempoCoordinator.lastReleaseCall();
        assertEq(recipient, address(0), "dust should not trigger release");
        assertEq(releasedAmount, 0, "dust should not mint local units");
        assertEq(tempoCoordinator.failedMessageExecutions(messageId), bytes32(0), "dust should not record failure");
    }

    function test_rollbackUsesNormalizedAmountAfterInboundFailure() public {
        uint256 localAmount = 2_500_000;
        uint256 canonicalAmount = localAmount * SCALE + 999;
        bytes32 tempoRecipient = tempoCoordinator.encodeOmnichainAddress(makeAddr("tempoRecipient"));
        bytes memory remoteMessage = _encodeBridgeMessage(
            remoteCoordinator, remoteUser, tempoRecipient, bytes32(0), bytes32(0), canonicalAmount
        );
        bytes memory bridgeOptions = buildReceiveOptions(200_000);
        uint256 inboundFee = remoteAdapter.estimateBridgeFee(CHAIN_ID_TEMPO, remoteMessage, bridgeOptions);

        tempoCoordinator.setFailRelease(true);

        vm.deal(remoteUser, inboundFee);
        vm.prank(remoteUser);
        bytes32 originalMessageId = remoteCoordinator.bridge{ value: inboundFee }(
            BRIDGE_TYPE,
            CHAIN_ID_TEMPO,
            remoteUser,
            tempoRecipient,
            address(0),
            bytes32(0),
            canonicalAmount,
            bridgeOptions
        );

        verifyPackets(EID_TEMPO, address(tempoAdapter));

        bytes memory normalizedMessage =
            _encodeBridgeMessage(tempoCoordinator, remoteUser, tempoRecipient, bytes32(0), bytes32(0), localAmount);
        assertEq(
            tempoCoordinator.failedMessageExecutions(originalMessageId),
            keccak256(abi.encode(CHAIN_ID_REMOTE, normalizedMessage)),
            "failed message should use normalized tempo payload"
        );

        bytes memory rollbackMessage = _encodeBridgeMessage(
            tempoCoordinator,
            address(0),
            remoteCoordinator.encodeOmnichainAddress(remoteUser),
            bytes32(0),
            bytes32(0),
            localAmount
        );
        uint256 rollbackFee = tempoAdapter.estimateBridgeFee(CHAIN_ID_REMOTE, rollbackMessage, bridgeOptions);

        vm.deal(refundAddress, rollbackFee);
        vm.prank(refundAddress);
        bytes32 rollbackMessageId = tempoCoordinator.rollback{ value: rollbackFee }(
            BRIDGE_TYPE, CHAIN_ID_REMOTE, normalizedMessage, originalMessageId, bridgeOptions
        );

        assertEq(
            tempoCoordinator.failedMessageExecutions(originalMessageId), bytes32(0), "failed message should be cleared"
        );

        assertTrue(hasPendingPackets(EID_REMOTE, remoteAdapterId), "rollback packet not queued");
        bytes memory packet = getNextInflightPacket(EID_REMOTE, remoteAdapterId);
        this.assertPacketBridgeAmount(
            packet, localAmount * SCALE, rollbackMessageId, remoteCoordinator.encodeOmnichainAddress(remoteUser)
        );
    }

    function assertPacketBridgeAmount(
        bytes calldata packet,
        uint256 expectedAmount,
        bytes32 expectedMessageId,
        bytes32 expectedRecipient
    )
        external
        view
    {
        require(msg.sender == address(this), "self-call only");

        (bytes memory forwardedMessage, bytes32 forwardedMessageId) = abi.decode(packet.message(), (bytes, bytes32));
        Message memory message = abi.decode(forwardedMessage, (Message));
        BridgeMessage memory bridgeMessage = abi.decode(message.data, (BridgeMessage));

        assertEq(packet.receiver(), remoteAdapterId, "receiver mismatch");
        assertEq(forwardedMessageId, expectedMessageId, "message id mismatch");
        assertEq(bridgeMessage.amount, expectedAmount, "bridge amount mismatch");
        assertEq(bridgeMessage.recipient, expectedRecipient, "recipient mismatch");
    }

    function buildReceiveOptions(uint128 gasLimit) internal pure returns (bytes memory) {
        bytes memory lzReceiveOption = ExecutorOptions.encodeLzReceiveOption(gasLimit, 0);
        uint16 optionSize = uint16(lzReceiveOption.length + 1);
        return abi.encodePacked(uint16(3), EXECUTOR_WORKER_ID, optionSize, OPTION_TYPE_LZRECEIVE, lzReceiveOption);
    }

    function _initializeCoordinator(BaseBridgeCoordinatorHarness coordinator) internal {
        vm.store(address(coordinator), coordinator.exposed_initializableStorageSlot(), bytes32(0));
        coordinator.initialize(unitToken, owner);
    }

    function _encodeBridgeMessage(
        BaseBridgeCoordinatorHarness coordinator,
        address sender,
        bytes32 recipient,
        bytes32 sourceWhitelabel,
        bytes32 destinationWhitelabel,
        uint256 amount
    )
        internal
        pure
        returns (bytes memory)
    {
        return coordinator.encodeBridgeMessage(
            BridgeMessage({
                sender: sender == address(0) ? bytes32(0) : coordinator.encodeOmnichainAddress(sender),
                recipient: recipient,
                sourceWhitelabel: sourceWhitelabel,
                destinationWhitelabel: destinationWhitelabel,
                amount: amount
            })
        );
    }
}
