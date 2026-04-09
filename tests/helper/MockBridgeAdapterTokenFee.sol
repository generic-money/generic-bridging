// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IBridgeAdapterTokenFee } from "../../src/interfaces/IBridgeAdapterTokenFee.sol";

contract MockBridgeAdapterTokenFee is IBridgeAdapterTokenFee {
    uint16 private immutable _bridgeType;
    address private immutable _coordinator;
    address private immutable _feeToken;

    // forge-lint: disable-next-line(mixed-case-function)
    function NATIVE_BRIDGING_FEES() public pure returns (bool) {
        return false;
    }

    function feeToken() external view returns (address) {
        return _feeToken;
    }

    struct BridgeCallParams {
        uint256 chainId;
        bytes32 remoteAdapter;
        bytes message;
        address refundAddress;
        bytes bridgeParams;
        bytes32 messageId;
    }

    BridgeCallParams public lastBridgeCall;

    constructor(uint16 bridgeType_, address coordinator_, address feeToken_) {
        _bridgeType = bridgeType_;
        _coordinator = coordinator_;
        _feeToken = feeToken_;
    }

    function bridge(
        uint256 chainId,
        bytes32 remoteAdapter,
        bytes calldata message,
        address refundAddress,
        bytes calldata bridgeParams,
        bytes32 messageId,
        uint256 fee
    )
        external
    {
        require(fee == estimateBridgeFee(chainId, message, bridgeParams), "Incorrect fee sent");
        lastBridgeCall = BridgeCallParams({
            chainId: chainId,
            remoteAdapter: remoteAdapter,
            message: message,
            refundAddress: refundAddress,
            bridgeParams: bridgeParams,
            messageId: messageId
        });
    }

    function estimateBridgeFee(uint256, bytes calldata, bytes calldata) public pure returns (uint256 nativeFee) {
        return 1 ether; // flat fee for testing
    }

    function bridgeType() external view returns (uint16) {
        return _bridgeType;
    }

    function bridgeCoordinator() external view returns (address) {
        return _coordinator;
    }
}
