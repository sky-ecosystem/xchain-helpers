// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { OAppReceiver, OAppCore, Origin } from "layerzerolabs/oapp-evm/contracts/oapp/OAppReceiver.sol";

struct MessageOrigin {
    uint32  srcEid;
    bytes32 srcSender;
}

contract GovernanceOAppReceiverMock is OAppReceiver, ReentrancyGuard {

    error GovernanceCallFailed();

    event GovernanceCallReceived(bytes32 indexed guid);

    MessageOrigin private _messageOrigin;

    constructor(
        uint32  _governanceOAppSenderEid,
        bytes32 _governanceOAppSenderAddress,
        address _endpoint,
        address _owner
    ) OAppCore(_endpoint, _owner) Ownable(_owner) {
        _setPeer(_governanceOAppSenderEid, _governanceOAppSenderAddress);
    }

    function messageOrigin() external view returns (MessageOrigin memory) {
        return _messageOrigin;
    }

    function setMessageOrigin(uint32 srcEid, bytes32 srcSender) external {
        _messageOrigin = MessageOrigin({ srcEid: srcEid, srcSender: srcSender });
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _payload,
        address,
        bytes calldata
    ) internal override nonReentrant {
        bytes32 srcSender = bytes32(_payload[0:32]);
        address dstTarget = address(uint160(bytes20(_payload[44:64])));
        bytes memory dstCallData = _payload[64:];

        _messageOrigin = MessageOrigin({ srcEid: _origin.srcEid, srcSender: srcSender });

        (bool success, bytes memory returnData) = dstTarget.call{ value: msg.value }(dstCallData);
        if (!success) {
            if (returnData.length == 0) revert GovernanceCallFailed();
            assembly ("memory-safe") {
                revert(add(32, returnData), mload(returnData))
            }
        }

        _messageOrigin = MessageOrigin({ srcEid: 0, srcSender: bytes32(0) });

        emit GovernanceCallReceived(_guid);
    }

}
