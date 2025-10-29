// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BridgeCoordinatorL1, PredepositCoordinator } from "../../src/BridgeCoordinatorL1.sol";
import { IBridgeAdapter } from "../../src/interfaces/IBridgeAdapter.sol";

contract BridgeCoordinatorL1Harness is BridgeCoordinatorL1 {
    function _storage() private pure returns (PredepositCoordinatorStorage storage $) {
        assembly {
            $.slot := 0xc21018d819991b3ffe7c98205610e4fd64c7a07a5010749045af9b9d7860c300
        }
    }

    function exposed_initializableStorageSlot() external pure returns (bytes32) {
        return _initializableStorageSlot();
    }

    function exposed_restrictShares(address whitelabel, address owner, uint256 amount) external {
        _restrictShares(whitelabel, owner, amount);
    }

    function exposed_releaseShares(address whitelabel, address receiver, uint256 amount) external {
        _releaseShares(whitelabel, receiver, amount);
    }

    function workaround_setOutboundLocalBridgeAdapter(uint16 bridgeType, address adapter) external {
        bridgeTypes[bridgeType].local.adapter = IBridgeAdapter(adapter);
    }

    function workaround_setOutboundRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter
    )
        external
    {
        bridgeTypes[bridgeType].remote[chainId].adapter = adapter;
    }

    function workaround_setPredepositState(
        bytes32 chainNickname,
        PredepositCoordinator.PredepositState state
    )
        external
    {
        _storage().chain[chainNickname].state = state;
    }

    function workaround_setPredepositChainId(bytes32 chainNickname, uint256 chainId) external {
        _storage().chain[chainNickname].chainId = chainId;
    }

    function workaround_setPredeposit(
        bytes32 chainNickname,
        address sender,
        bytes32 recipient,
        uint256 amount
    )
        external
    {
        PredepositCoordinatorStorage storage $ = _storage();
        $.chain[chainNickname].predeposits[sender][recipient] = amount;
    }

    function workaround_setTotalPredeposits(bytes32 chainNickname, uint256 totalAmount) external {
        PredepositCoordinatorStorage storage $ = _storage();
        $.chain[chainNickname].totalPredeposits = totalAmount;
    }
}
