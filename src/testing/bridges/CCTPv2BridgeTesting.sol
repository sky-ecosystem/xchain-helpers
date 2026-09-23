// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Vm } from "forge-std/Vm.sol";

import { Bridge, BridgeType }    from "../Bridge.sol";
import { Domain, DomainHelpers } from "../Domain.sol";
import { RecordedLogs }          from "../utils/RecordedLogs.sol";

import { CCTPv2Forwarder } from "../../forwarders/CCTPv2Forwarder.sol";

interface IMessengerV2 {
    function localDomain() external view returns (uint32);
    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool success);
}

library CCTPv2BridgeTesting {

    using DomainHelpers for *;
    using RecordedLogs  for *;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private constant SENT_MESSAGE_TOPIC = keccak256("MessageSent(bytes)");

    function createCircleBridge(Domain memory source, Domain memory destination) internal returns (Bridge memory bridge) {
        return init(Bridge({
            bridgeType                     : BridgeType.CCTP_V2,
            source                         : source,
            destination                    : destination,
            sourceCrossChainMessenger      : getCircleMessengerFromChainAlias(source.chain.chainAlias),
            destinationCrossChainMessenger : getCircleMessengerFromChainAlias(destination.chain.chainAlias),
            lastSourceLogIndex             : 0,
            lastDestinationLogIndex        : 0,
            extraData                      : ""
        }));
    }

    function getCircleMessengerFromChainAlias(string memory chainAlias) internal pure returns (address) {
        bytes32 name = keccak256(bytes(chainAlias));

        if (name == keccak256("mainnet")) {
            return CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ETHEREUM;
        } else if (name == keccak256("optimism")) {
            return CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_OPTIMISM;
        } else if (name == keccak256("arbitrum_one")) {
            return CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ARBITRUM_ONE;
        } else if (name == keccak256("base")) {
            return CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_BASE;
        } else if (name == keccak256("unichain")) {
            return CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_UNICHAIN;
        } else {
            revert("Unsupported chain");
        }
    }

    function init(Bridge memory bridge) internal returns (Bridge memory) {
        // Set minimum required signatures to zero for both domains
        bridge.destination.selectFork();
        vm.store(
            bridge.destinationCrossChainMessenger,
            bytes32(uint256(4)),  // `signatureThreshold` slot
            0
        );
        bridge.source.selectFork();
        vm.store(
            bridge.sourceCrossChainMessenger,
            bytes32(uint256(4)),
            0
        );

        RecordedLogs.init();

        return bridge;
    }

    function relayMessagesToDestination(Bridge storage bridge, bool switchToDestinationFork) internal {
        // Get source domain while still on source fork
        bridge.source.selectFork();
        uint32 sourceDomain = IMessengerV2(bridge.sourceCrossChainMessenger).localDomain();

        bridge.destination.selectFork();

        Vm.Log[] memory logs = bridge.ingestAndFilterLogs(true, SENT_MESSAGE_TOPIC, bridge.sourceCrossChainMessenger);
        uint32 destinationDomain = IMessengerV2(bridge.destinationCrossChainMessenger).localDomain();
        for (uint256 i = 0; i < logs.length; i++) {
            bytes memory message = abi.decode(logs[i].data, (bytes));
            uint32 messageDestinationDomain = getDestinationDomain(message);
            uint32 messageSourceDomain = getSourceDomain(message);
            if (messageDestinationDomain == destinationDomain && messageSourceDomain == sourceDomain) {
                IMessengerV2(bridge.destinationCrossChainMessenger).receiveMessage(processMessage(message), "");
            }
        }

        if (!switchToDestinationFork) {
            bridge.source.selectFork();
        }
    }

    function relayMessagesToSource(Bridge storage bridge, bool switchToSourceFork) internal {
        // Get destination domain before switching to source fork
        bridge.destination.selectFork();
        uint32 destinationDomain = IMessengerV2(bridge.destinationCrossChainMessenger).localDomain();

        bridge.source.selectFork();

        Vm.Log[] memory logs = bridge.ingestAndFilterLogs(false, SENT_MESSAGE_TOPIC, bridge.destinationCrossChainMessenger);
        uint32 sourceDomain = IMessengerV2(bridge.sourceCrossChainMessenger).localDomain();
        for (uint256 i = 0; i < logs.length; i++) {
            bytes memory message = abi.decode(logs[i].data, (bytes));
            uint32 messageDestinationDomain = getDestinationDomain(message);
            uint32 messageSourceDomain = getSourceDomain(message);
            if (messageDestinationDomain == sourceDomain && messageSourceDomain == destinationDomain) {
                IMessengerV2(bridge.sourceCrossChainMessenger).receiveMessage(processMessage(message), "");
            }
        }

        if (!switchToSourceFork) {
            bridge.destination.selectFork();
        }
    }

    /**
     * @notice Extracts the destinationDomain (a uint32) from a message.
     * @param  message The encoded message as a bytes array.
     * @return destinationDomain The extracted destinationDomain.
     *
     * Message format:
     * Field                        Bytes      Type       Index
     * version                      4          uint32     0
     * sourceDomain                 4          uint32     4
     * destinationDomain            4          uint32     8
     * nonce                        32         bytes32    12
     * sender                       32         bytes32    44
     * recipient                    32         bytes32    76
     * destinationCaller            32         bytes32    108
     * minFinalityThreshold         4          uint32     140
     * finalityThresholdExecuted    4          uint32     144
     * messageBody                  dynamic    bytes      148
     */
    function getDestinationDomain(bytes memory message) public pure returns (uint32 destinationDomain) {
        require(message.length >= 12, "Message too short");
        assembly {
            // Add 32 to skip the length word, then add 8 to reach the destinationDomain.
            // mload loads 32 bytes starting from that position.
            // The actual uint32 is in the top 4 bytes, so shift right by 224 bits.
            destinationDomain := shr(224, mload(add(message, 40)))
        }
    }

    /**
     * @notice Extracts the sourceDomain (a uint32) from a message.
     * @param  message The encoded message as a bytes array.
     * @return sourceDomain The extracted sourceDomain.
     */
    function getSourceDomain(bytes memory message) public pure returns (uint32 sourceDomain) {
        require(message.length >= 8, "Message too short");
        assembly {
            sourceDomain := shr(224, mload(add(message, 36)))
        }
    }

    /**
     * @notice Processes a given CCTPv2 message, updating the nonce to a random value and setting the finality threshold executed field.
     * @param message The original encoded message as a bytes array.
     * @return processedMessage The processed message with updated nonce and finality threshold executed fields.
     *
     * The function clones the original message, replaces the nonce (bytes 12-43) with a pseudo-random value, and sets
     * the "finality threshold executed" (bytes 144-147) to match "min finality threshold" (bytes 140-143).
     */
    function processMessage(bytes memory message) internal view returns (bytes memory processedMessage) {
        require(message.length >= 148, "CCTPv2BridgeTesting/message-too-short");

        processedMessage = abi.encodePacked(message);

        // Add a random nonce
        bytes32 newNonce = keccak256(
            abi.encodePacked(
                msg.sender,
                block.timestamp,
                block.number,
                block.prevrandao,
                gasleft(),
                message,
                address(this)
            )
        );
        assembly {
            mstore(add(add(processedMessage, 32), 12), newNonce)
        }

        // Set the finality threshold executed
        assembly {
            let base := add(processedMessage, 32)

            let threshold := shr(224, mload(add(base, 140)))  // uint32

            let p := add(base, 144)
            let word := mload(p)

            let mask := 0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            let kept := and(word, mask)

            mstore(p, or(kept, shl(224, threshold)))
        }
    }

}
