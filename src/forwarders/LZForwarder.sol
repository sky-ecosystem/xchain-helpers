// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

struct MessagingParams {
    uint32  dstEid;
    bytes32 receiver;
    bytes   message;
    bytes   options;
    bool    payInLzToken;
}

struct MessagingReceipt {
    bytes32      guid;
    uint64       nonce;
    MessagingFee fee;
}

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

interface ILayerZeroEndpointV2 {
    function send(
        MessagingParams calldata _params,
        address                  _refundAddress
    ) external payable returns (MessagingReceipt memory);
    function quote(
        MessagingParams calldata _params,
        address                  _sender
    ) external view returns (MessagingFee memory);
}

library LZForwarder {

    uint32 public constant ENDPOINT_ID_BASE     = 30184;
    uint32 public constant ENDPOINT_ID_BNB      = 30102;
    uint32 public constant ENDPOINT_ID_ETHEREUM = 30101;

    address public constant ENDPOINT_BASE     = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant ENDPOINT_BNB      = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant ENDPOINT_ETHEREUM = 0x1a44076050125825900e736c501f859c50fE728c;

    address public constant RECEIVE_LIBRARY_BASE     = 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf;
    address public constant RECEIVE_LIBRARY_BNB      = 0xB217266c3A98C8B2709Ee26836C98cf12f6cCEC1;
    address public constant RECEIVE_LIBRARY_ETHEREUM = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;

    function sendMessage(
        uint32               _dstEid,
        bytes32              _receiver,
        ILayerZeroEndpointV2 endpoint,
        bytes         memory _message,
        bytes         memory _options,
        address              _refundAddress
    ) internal {
        MessagingParams memory params = MessagingParams({
            dstEid:       _dstEid,
            receiver:     _receiver,
            message:      _message,
            options:      _options,
            payInLzToken: false
        });

        MessagingFee memory fee = endpoint.quote(params, msg.sender);

        endpoint.send{ value: fee.nativeFee }(params, _refundAddress);
    }

}
