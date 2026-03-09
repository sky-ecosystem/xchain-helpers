// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

struct TxParams {
    uint32  dstEid;
    bytes32 dstTarget;
    bytes   dstCallData;
    bytes   extraOptions;
}

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

struct MessagingReceipt {
    bytes32 guid;
    uint64  nonce;
    MessagingFee fee;
}

interface IGovOapp {
    function quoteTx(TxParams calldata _params, bool _payInLzToken) external view returns (MessagingFee memory fee);
    function sendTx(TxParams calldata _params, MessagingFee calldata _fee, address _refundAddress) external payable returns (MessagingReceipt memory msgReceipt);
}

library LzGovBridgeForwarder {

    function quote(
        address govOapp,
        uint32  dstEid,
        address dstTarget,
        bytes memory message,
        bytes memory extraOptions
    ) internal view returns (MessagingFee memory) {

        return IGovOapp(govOapp).quoteTx({
            _params: TxParams({
                dstEid:      dstEid,
                dstTarget:   bytes32(uint256(uint160(dstTarget))),
                dstCallData: message,
                extraOptions: extraOptions
            }),
            _payInLzToken: false
        });
    }

    function sendMessage(
        address govOapp,
        uint32  dstEid,
        address dstTarget,
        bytes memory message,
        bytes memory extraOptions,
        address refundAddress
    ) internal returns (MessagingReceipt memory) {

        return IGovOapp(govOapp).sendTx{ value: msg.value }({
            _params: TxParams({
                dstEid:      dstEid,
                dstTarget:   bytes32(uint256(uint160(dstTarget))),
                dstCallData: message,
                extraOptions: extraOptions
            }),
            _fee:           MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 }),
            _refundAddress: refundAddress
        });
    }

}
