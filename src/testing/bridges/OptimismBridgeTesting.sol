// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Vm }        from "forge-std/Vm.sol";

import { Bridge, BridgeType }    from "../Bridge.sol";
import { Domain, DomainHelpers } from "../Domain.sol";
import { RecordedLogs }          from "../utils/RecordedLogs.sol";
import { OptimismForwarder }     from "../../forwarders/OptimismForwarder.sol";

interface IMessenger {
    function sendMessage(
        address target,
        bytes memory message,
        uint32 gasLimit
    ) external;
    function relayMessage(
        uint256 _nonce,
        address _sender,
        address _target,
        uint256 _value,
        uint256 _minGasLimit,
        bytes calldata _message
    ) external payable;
}

library OptimismBridgeTesting {

    using DomainHelpers for *;
    using RecordedLogs  for *;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private constant SENT_MESSAGE_TOPIC = keccak256("SentMessage(address,address,bytes,uint256,uint256)");

    function createNativeBridge(Domain memory ethereum, Domain memory optimismInstance) internal returns (Bridge memory bridge) {
        (
            address sourceCrossChainMessenger,
            address destinationCrossChainMessenger
        ) = getMessengerFromChainAlias(ethereum.chain.chainAlias, optimismInstance.chain.chainAlias);

        return init(Bridge({
            bridgeType:                     BridgeType.OPTIMISM,
            source:                         ethereum,
            destination:                    optimismInstance,
            sourceCrossChainMessenger:      sourceCrossChainMessenger,
            destinationCrossChainMessenger: destinationCrossChainMessenger,
            lastSourceLogIndex:             0,
            lastDestinationLogIndex:        0,
            extraData:                      ""
        }));
    }

    function getMessengerFromChainAlias(
        string memory sourceChainAlias,
        string memory destinationChainAlias
    ) internal pure returns (
        address sourceCrossChainMessenger,
        address destinationCrossChainMessenger
    ) {
        require(keccak256(bytes(sourceChainAlias)) == keccak256("mainnet"), "Source must be Ethereum.");

        bytes32 name = keccak256(bytes(destinationChainAlias));
        if (name == keccak256("optimism")) {
            sourceCrossChainMessenger = OptimismForwarder.L1_CROSS_DOMAIN_OPTIMISM;
        } else if (name == keccak256("base")) {
            sourceCrossChainMessenger = OptimismForwarder.L1_CROSS_DOMAIN_BASE;
        } else if (name == keccak256("world_chain")) {
            sourceCrossChainMessenger = OptimismForwarder.L1_CROSS_DOMAIN_WORLD_CHAIN;
        } else if (name == keccak256("unichain")) {
            sourceCrossChainMessenger = OptimismForwarder.L1_CROSS_DOMAIN_UNICHAIN;
        } else if (name == keccak256("xlayer")) {
            sourceCrossChainMessenger = OptimismForwarder.L1_CROSS_DOMAIN_XLAYER;
        } else {
            revert("Unsupported destination chain");
        }
        destinationCrossChainMessenger = 0x4200000000000000000000000000000000000007;
    }

    function init(Bridge memory bridge) internal returns (Bridge memory) {
        RecordedLogs.init();

        // For consistency with other bridges
        bridge.source.selectFork();

        return bridge;
    }

    function relayMessagesToDestination(Bridge storage bridge, bool switchToDestinationFork) internal {
        bridge.destination.selectFork();

        address malias;
        unchecked {
            malias = address(uint160(bridge.sourceCrossChainMessenger) + uint160(0x1111000000000000000000000000000000001111));
        }

        Vm.Log[] memory logs = bridge.ingestAndFilterLogs(true, SENT_MESSAGE_TOPIC, bridge.sourceCrossChainMessenger);
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            address target = address(uint160(uint256(log.topics[1])));
            (address sender, bytes memory message, uint256 nonce, uint256 gasLimit) = abi.decode(log.data, (address, bytes, uint256, uint256));
            vm.prank(malias);
            IMessenger(bridge.destinationCrossChainMessenger).relayMessage(nonce, sender, target, 0, gasLimit, message);
        }

        if (!switchToDestinationFork) {
            bridge.source.selectFork();
        }
    }

    function relayMessagesToSource(Bridge storage bridge, bool switchToSourceFork) internal {
        bridge.source.selectFork();

        Vm.Log[] memory logs = bridge.ingestAndFilterLogs(false, SENT_MESSAGE_TOPIC, bridge.destinationCrossChainMessenger);
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            address target = address(uint160(uint256(log.topics[1])));
                (address sender, bytes memory message,,) = abi.decode(log.data, (address, bytes, uint256, uint256));
                // Set xDomainMessageSender
                vm.store(
                    bridge.sourceCrossChainMessenger,
                    bytes32(uint256(204)),
                    bytes32(uint256(uint160(sender)))
                );
                vm.startPrank(bridge.sourceCrossChainMessenger);
                (bool success, bytes memory response) = target.call(message);
                vm.stopPrank();
                vm.store(
                    bridge.sourceCrossChainMessenger,
                    bytes32(uint256(204)),
                    bytes32(uint256(0))
                );
                if (!success) {
                    assembly {
                        revert(add(response, 32), mload(response))
                    }
                }
        }

        if (!switchToSourceFork) {
            bridge.destination.selectFork();
        }
    }

}
