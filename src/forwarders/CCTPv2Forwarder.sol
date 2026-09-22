// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

interface IMessageTransmitterV2 {
    function sendMessage(
        uint32 destinationDomain,
        bytes32 recipient,
        bytes32 destinationCaller,    // 0x0 = anyone can relay
        uint32 minFinalityThreshold,  // 2000 = standard (finalized), 1000 = fast (unfinalized)
        bytes calldata messageBody
    ) external;
}

library CCTPv2Forwarder {

    address internal constant MESSAGE_TRANSMITTER_CIRCLE_ETHEREUM     = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;
    address internal constant MESSAGE_TRANSMITTER_CIRCLE_OPTIMISM     = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;
    address internal constant MESSAGE_TRANSMITTER_CIRCLE_ARBITRUM_ONE = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;
    address internal constant MESSAGE_TRANSMITTER_CIRCLE_BASE         = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;
    address internal constant MESSAGE_TRANSMITTER_CIRCLE_UNICHAIN     = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;

    uint32 internal constant DOMAIN_ID_CIRCLE_ETHEREUM     = 0;
    uint32 internal constant DOMAIN_ID_CIRCLE_OPTIMISM     = 2;
    uint32 internal constant DOMAIN_ID_CIRCLE_ARBITRUM_ONE = 3;
    uint32 internal constant DOMAIN_ID_CIRCLE_BASE         = 6;

    uint32 internal constant V2_MIN_FINALITY_STANDARD = 2_000;

    bytes32 internal constant V2_DESTINATION_CALLER_ANY = bytes32(0);

    function sendMessage(
        address      messageTransmitter,
        uint32       destinationDomainId,
        bytes32      recipient,
        bytes memory messageBody
    ) internal {
        IMessageTransmitterV2(messageTransmitter).sendMessage(
            destinationDomainId,
            recipient,
            V2_DESTINATION_CALLER_ANY,
            V2_MIN_FINALITY_STANDARD,
            messageBody
        );
    }

    function sendMessage(
        address      messageTransmitter,
        uint32       destinationDomainId,
        address      recipient,
        bytes memory messageBody
    ) internal {
        sendMessage(
            messageTransmitter,
            destinationDomainId,
            bytes32(uint256(uint160(recipient))),
            messageBody
        );
    }
}
