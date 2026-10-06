// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0;

struct MessageOrigin {
    uint32  srcEid;
    bytes32 srcSender;
}

contract GovernanceOAppReceiverMock {

    MessageOrigin private _messageOrigin;

    function messageOrigin() external view returns (MessageOrigin memory) {
        return _messageOrigin;
    }

    function setMessageOrigin(uint32 srcEid, bytes32 srcSender) external {
        _messageOrigin = MessageOrigin({ srcEid: srcEid, srcSender: srcSender });
    }

}
