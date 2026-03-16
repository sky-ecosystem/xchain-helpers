// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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

library LZGovBridgeForwarder {

    uint32 public constant ENDPOINT_ID_BASE     = 30184;
    uint32 public constant ENDPOINT_ID_BNB      = 30102;
    uint32 public constant ENDPOINT_ID_ETHEREUM = 30101;

    address public constant ENDPOINT_BASE = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant ENDPOINT_BNB  = 0x1a44076050125825900e736c501f859c50fE728c;

    // `quote` is provided separately to allow callers to send the exact fee amount to the forwarder
    function quote(
        address govOapp,
        uint32  dstEid,
        address dstTarget,
        bytes memory message,
        bytes memory extraOptions,
        bool payInLzToken
    ) internal view returns (MessagingFee memory) {

        return IGovOapp(govOapp).quoteTx({
            _params: TxParams({
                dstEid:      dstEid,
                dstTarget:   bytes32(uint256(uint160(dstTarget))),
                dstCallData: message,
                extraOptions: extraOptions
            }),
            _payInLzToken: payInLzToken
        });
    }

    // It is the caller's responsibility to ensure the correct lzToken address is passed.
    function sendMessage(
        address govOapp,
        uint32  dstEid,
        address dstTarget,
        bytes memory message,
        bytes memory extraOptions,
        address refundAddress,
        MessagingFee memory fee,
        address lzToken
    ) internal returns (MessagingReceipt memory) {

        if (fee.lzTokenFee > 0) IERC20(lzToken).approve(govOapp, fee.lzTokenFee);

        return IGovOapp(govOapp).sendTx{ value: fee.nativeFee }({
            _params: TxParams({
                dstEid:      dstEid,
                dstTarget:   bytes32(uint256(uint160(dstTarget))),
                dstCallData: message,
                extraOptions: extraOptions
            }),
            _fee:           fee,
            _refundAddress: refundAddress
        });
    }

}
