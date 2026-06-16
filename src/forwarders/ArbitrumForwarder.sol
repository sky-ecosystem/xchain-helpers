// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

interface ICrossDomainArbitrum {
    function createRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        bytes calldata data
    ) external payable returns (uint256);
    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee) external view returns (uint256);
}

interface IArbSys {
    function sendTxToL1(address target, bytes calldata message) external;
}

library ArbitrumForwarder {

    address constant internal L1_CROSS_DOMAIN_ARBITRUM_ONE    = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;
    address constant internal L1_CROSS_DOMAIN_ARBITRUM_NOVA   = 0xc4448b71118c9071Bcb9734A0EAc55D18A153949;
    address constant internal L1_CROSS_DOMAIN_ROBINHOOD_CHAIN = 0x59014B601E530494665888E73113734222457046;  // TODO: add the correct address
    address constant internal L2_CROSS_DOMAIN                 = 0x0000000000000000000000000000000000000064;

    function sendMessageL1toL2(
        address l1CrossDomain,
        address target,
        bytes memory message,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 baseFee
    ) internal {
        uint256 maxSubmission = ICrossDomainArbitrum(l1CrossDomain).calculateRetryableSubmissionFee(message.length, baseFee);
        uint256 maxRedemption = gasLimit * maxFeePerGas;
        ICrossDomainArbitrum(l1CrossDomain).createRetryableTicket{value: maxSubmission + maxRedemption}(
            target,
            0, // we always assume that l2CallValue = 0
            maxSubmission,
            address(0), // burn the excess gas
            address(0), // burn the excess gas
            gasLimit,
            maxFeePerGas,
            message
        );
    }

    function sendMessageL2toL1(
        address target,
        bytes memory message
    ) internal {
        IArbSys(L2_CROSS_DOMAIN).sendTxToL1(
            target,
            message
        );
    }
    
}
