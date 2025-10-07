// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Vm } from "forge-std/Vm.sol";

import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { Bridge, BridgeType }    from "../Bridge.sol";
import { Domain, DomainHelpers } from "../Domain.sol";
import { RecordedLogs }          from "../utils/RecordedLogs.sol";
import { LZForwarder }           from "../../forwarders/LZForwarder.sol";

struct Origin {
    uint32  srcEid;
    bytes32 sender;
    uint64  nonce;
}

interface IEndpoint {
    function eid() external view returns (uint32);
    function verify(Origin calldata _origin, address _receiver, bytes32 _payloadHash) external;
    function lzReceive(
        Origin calldata _origin,
        address _receiver,
        bytes32 _guid,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable;
}

contract PacketBytesHelper {

    function srcEid(bytes calldata packetBytes) external pure returns (uint32) {
        return PacketV1Codec.srcEid(packetBytes);
    }

    function nonce(bytes calldata packetBytes) external pure returns (uint64) {
        return PacketV1Codec.nonce(packetBytes);
    }

    function dstEid(bytes calldata packetBytes) external pure returns (uint32) {
        return PacketV1Codec.dstEid(packetBytes);
    }

    function guid(bytes calldata packetBytes) external pure returns (bytes32) {
        return PacketV1Codec.guid(packetBytes);
    }
    
    function message(bytes calldata packetBytes) external pure returns (bytes memory) {
        return PacketV1Codec.message(packetBytes);
    }

}

library LZBridgeTesting {

    bytes32 private constant PACKET_SENT_TOPIC = keccak256("PacketSent(bytes,bytes,address)");

    using DomainHelpers for *;
    using RecordedLogs  for *;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function createLZBridge(Domain memory source, Domain memory destination) internal returns (Bridge memory bridge) {
        return init(Bridge({
            bridgeType:                     BridgeType.LZ,
            source:                         source,
            destination:                    destination,
            sourceCrossChainMessenger:      getLZEndpointFromChainAlias(source.chain.chainAlias),
            destinationCrossChainMessenger: getLZEndpointFromChainAlias(destination.chain.chainAlias),
            lastSourceLogIndex:             0,
            lastDestinationLogIndex:        0,
            extraData:                      abi.encode(getReceiveLibraryFromChainAlias(source.chain.chainAlias), getReceiveLibraryFromChainAlias(destination.chain.chainAlias))
        }));
    }

    function getLZEndpointFromChainAlias(string memory chainAlias) internal pure returns (address) {
        bytes32 name = keccak256(bytes(chainAlias));
        if (name == keccak256("mainnet")) {
            return LZForwarder.ENDPOINT_ETHEREUM;
        } else if (name == keccak256("base")) {
            return LZForwarder.ENDPOINT_BASE;
        } else if (name == keccak256("bnb_smart_chain")) {
            return LZForwarder.ENDPOINT_BNB;
        } else if (name == keccak256("avalanche")) {
            return LZForwarder.ENDPOINT_AVALANCHE;
        } else {
            revert("Unsupported chain");
        }
    }

    function getReceiveLibraryFromChainAlias(string memory chainAlias) internal pure returns (address) {
        bytes32 name = keccak256(bytes(chainAlias));
        if (name == keccak256("mainnet")) {
            return LZForwarder.RECEIVE_LIBRARY_ETHEREUM;
        } else if (name == keccak256("base")) {
            return LZForwarder.RECEIVE_LIBRARY_BASE;
        } else if (name == keccak256("bnb_smart_chain")) {
            return LZForwarder.RECEIVE_LIBRARY_BNB;
        } else if (name == keccak256("avalanche")) {
            return LZForwarder.RECEIVE_LIBRARY_AVALANCHE;
        } else {
            revert("Unsupported chain");
        }
    }

    function init(Bridge memory bridge) internal returns (Bridge memory) {
        RecordedLogs.init();

        // For consistency with other bridges
        bridge.source.selectFork();

        return bridge;
    }

    function relayMessagesToDestination(
        Bridge storage bridge,
        bool           switchToDestinationFork,
        address        sender,
        address        receiver
    ) internal {
        bridge.destination.selectFork();

        Vm.Log[] memory logs = bridge.ingestAndFilterLogs(true, PACKET_SENT_TOPIC, bridge.sourceCrossChainMessenger);
        for (uint256 i = 0; i < logs.length; i++) {
            ( bytes memory encodedPacket,, ) = abi.decode(logs[i].data, (bytes, bytes, address));

            // Step 1: Parse data from encoded packet in event

            uint32 destinationEid = getDestinationEid(encodedPacket);
            bytes32 guid = getGuid(encodedPacket);
            bytes memory message = getMessage(encodedPacket);

            if (destinationEid == IEndpoint(bridge.destinationCrossChainMessenger).eid()) {
                ( , address destinationReceiveLibrary ) = abi.decode(bridge.extraData, (address, address));
                bytes32 payloadHash = keccak256(abi.encodePacked(guid, message));

                // Step 2: Prank as destinationReceiveLibrary to bypass DVN verification step, required before lzReceive can be called

                vm.startPrank(destinationReceiveLibrary);
                IEndpoint(bridge.destinationCrossChainMessenger).verify(
                    Origin({
                        srcEid: getSourceEid(encodedPacket),
                        sender: bytes32(uint256(uint160(sender))),
                        nonce:  getNonce(encodedPacket)
                    }),
                    receiver,
                    payloadHash
                );
                vm.stopPrank();

                // Step 3: Call permissionless lzReceive on endpoint now that payload is verified

                IEndpoint(bridge.destinationCrossChainMessenger).lzReceive(
                    Origin({
                        srcEid: getSourceEid(encodedPacket),
                        sender: bytes32(uint256(uint160(sender))),
                        nonce:  getNonce(encodedPacket)
                    }),
                    receiver,
                    guid,
                    message,
                    ""
                );
            }
        }

        if (!switchToDestinationFork) {
            bridge.source.selectFork();
        }
    }

    function relayMessagesToSource(
        Bridge storage bridge,
        bool           switchToSourceFork,
        address        sender,
        address        receiver
    ) internal {
        bridge.source.selectFork();

        Vm.Log[] memory logs = bridge.ingestAndFilterLogs(false, PACKET_SENT_TOPIC, bridge.destinationCrossChainMessenger);
        for (uint256 i = 0; i < logs.length; i++) {
            ( bytes memory encodedPacket,, ) = abi.decode(logs[i].data, (bytes, bytes, address));

            // Step 1: Parse data from encoded packet in event

            uint32 destinationEid = getDestinationEid(encodedPacket);  // NOTE: destinationEid in this case is for the source endpoint ID
            bytes32 guid = getGuid(encodedPacket);
            bytes memory message = getMessage(encodedPacket);

            if (destinationEid == IEndpoint(bridge.sourceCrossChainMessenger).eid()) {
                ( address sourceReceiveLibrary, ) = abi.decode(bridge.extraData, (address, address));
                bytes32 payloadHash = keccak256(abi.encodePacked(guid, message));

                // Step 2: Prank as destinationReceiveLibrary to bypass DVN verification step, required before lzReceive can be called

                vm.startPrank(sourceReceiveLibrary);
                IEndpoint(bridge.sourceCrossChainMessenger).verify(
                    Origin({
                        srcEid: getSourceEid(encodedPacket),
                        sender: bytes32(uint256(uint160(sender))),
                        nonce:  getNonce(encodedPacket)
                    }),
                    receiver,
                    payloadHash
                );
                vm.stopPrank();

                // Step 3: Call permissionless lzReceive on endpoint now that payload is verified

                IEndpoint(bridge.sourceCrossChainMessenger).lzReceive(
                    Origin({
                        srcEid: getSourceEid(encodedPacket),
                        sender: bytes32(uint256(uint160(sender))),
                        nonce:  getNonce(encodedPacket)
                    }),
                    receiver,
                    guid,
                    message,
                    ""
                );
            }
        }

        if (!switchToSourceFork) {
            bridge.destination.selectFork();
        }
    }

    function getDestinationEid(bytes memory encodedPacket) public returns (uint32) {
        return new PacketBytesHelper().dstEid(encodedPacket);
    }

    function getGuid(bytes memory encodedPacket) public returns (bytes32) {
        return new PacketBytesHelper().guid(encodedPacket);
    }

    function getMessage(bytes memory encodedPacket) public returns (bytes memory) {
        return new PacketBytesHelper().message(encodedPacket);
    }

    function getSourceEid(bytes memory encodedPacket) public returns (uint32) {
        return new PacketBytesHelper().srcEid(encodedPacket);
    }

    function getNonce(bytes memory encodedPacket) public returns (uint64) {
        return new PacketBytesHelper().nonce(encodedPacket);
    }

}
