// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Vm }        from "forge-std/Vm.sol";

import { Bridge, BridgeType }    from "../Bridge.sol";
import { Domain, DomainHelpers } from "../Domain.sol";
import { RecordedLogs }          from "../utils/RecordedLogs.sol";
import { ArbitrumForwarder }     from "../../forwarders/ArbitrumForwarder.sol";

interface InboxLike {
    function createRetryableTicket(
        address destAddr,
        uint256 arbTxCallValue,
        uint256 maxSubmissionCost,
        address submissionRefundAddress,
        address valueRefundAddress,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external payable returns (uint256);
    function bridge() external view returns (BridgeLike);
}

interface BridgeLike {
    function rollup() external view returns (address);
    function executeCall(
        address,
        uint256,
        bytes calldata
    ) external returns (bool, bytes memory);
    function setOutbox(address, bool) external;
}

contract ArbSysOverride {

    event SendTxToL1(address sender, address target, bytes data);

    function sendTxToL1(address target, bytes calldata message) external payable returns (uint256) {
        emit SendTxToL1(msg.sender, target, message);
        return 0;
    }

}

library ArbitrumBridgeTesting {

    using DomainHelpers for *;
    using RecordedLogs for *;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private constant MESSAGE_DELIVERED_TOPIC = keccak256("MessageDelivered(uint256,bytes32,address,uint8,address,bytes32,uint256,uint64)");
    bytes32 private constant SEND_TO_L1_TOPIC        = keccak256("SendTxToL1(address,address,bytes)");
    
    function createNativeBridge(Domain memory ethereum, Domain memory arbitrumInstance) internal returns (Bridge memory bridge) {
        (
            address sourceCrossChainMessenger,
            address destinationCrossChainMessenger
        ) = getMessengerFromChainAlias(ethereum.chain.chainAlias, arbitrumInstance.chain.chainAlias);

        return init(Bridge({
            bridgeType:                     BridgeType.ARBITRUM,
            source:                         ethereum,
            destination:                    arbitrumInstance,
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
        if (name == keccak256("arbitrum_one")) {
            sourceCrossChainMessenger = ArbitrumForwarder.L1_CROSS_DOMAIN_ARBITRUM_ONE;
        } else if (name == keccak256("arbitrum_nova")) {
            sourceCrossChainMessenger = ArbitrumForwarder.L1_CROSS_DOMAIN_ARBITRUM_NOVA;
        } else if (name == keccak256("robinhood_chain")) {
            sourceCrossChainMessenger = ArbitrumForwarder.L1_CROSS_DOMAIN_ROBINHOOD_CHAIN;
        } else {
            revert("Unsupported destination chain");
        }
        destinationCrossChainMessenger = 0x0000000000000000000000000000000000000064;
    }

    function init(Bridge memory bridge) internal returns (Bridge memory) {
        RecordedLogs.init();

        // Need to replace ArbSys contract with custom code to make it compatible with revm
        bridge.destination.selectFork();
        bytes memory bytecode = vm.getCode("ArbitrumBridgeTesting.sol:ArbSysOverride");
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        vm.etch(bridge.destinationCrossChainMessenger, deployed.code);

        bridge.source.selectFork();
        BridgeLike underlyingBridge = InboxLike(bridge.sourceCrossChainMessenger).bridge();
        bridge.extraData = abi.encode(address(underlyingBridge));

        // Make this contract a valid outbox
        address _rollup = underlyingBridge.rollup();
        vm.store(
            address(underlyingBridge),
            bytes32(uint256(8)),
            bytes32(uint256(uint160(address(this))))
        );
        underlyingBridge.setOutbox(address(this), true);
        vm.store(
            address(underlyingBridge),
            bytes32(uint256(8)),
            bytes32(uint256(uint160(_rollup)))
        );

        return bridge;
    }

    function relayMessagesToDestination(Bridge storage bridge, bool switchToDestinationFork) internal {
        bridge.destination.selectFork();

        Vm.Log[] memory logs = RecordedLogs.getLogs();
        for (; bridge.lastSourceLogIndex < logs.length; bridge.lastSourceLogIndex++) {
            Vm.Log memory log = logs[bridge.lastSourceLogIndex];
            if (log.topics[0] == MESSAGE_DELIVERED_TOPIC && log.emitter == abi.decode(bridge.extraData, (address))) {
                // We need both the current event and the one that follows for all the relevant data
                Vm.Log memory logWithData = logs[bridge.lastSourceLogIndex + 1];
                (,, address sender,,,) = abi.decode(log.data, (address, uint8, address, bytes32, uint256, uint64));
                (address target, bytes memory message) = _parseData(logWithData.data);
                vm.startPrank(sender);
                (bool success, bytes memory response) = target.call(message);
                vm.stopPrank();
                if (!success) {
                    assembly {
                        revert(add(response, 32), mload(response))
                    }
                }
            }
        }

        if (!switchToDestinationFork) {
            bridge.source.selectFork();
        }
    }

    function relayMessagesToSource(Bridge storage bridge, bool switchToSourceFork) internal {
        bridge.source.selectFork();

        Vm.Log[] memory logs = bridge.ingestAndFilterLogs(false, SEND_TO_L1_TOPIC, bridge.destinationCrossChainMessenger);
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            (, address target, bytes memory message) = abi.decode(log.data, (address, address, bytes));
            (bool success, bytes memory response) = InboxLike(bridge.sourceCrossChainMessenger).bridge().executeCall(target, 0, message);
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

    function _parseData(bytes memory orig) private pure returns (address target, bytes memory message) {
        // FIXME - this is not robust enough, only handling messages of a specific format
        uint256 mlen;
        (,,target ,,,,,,,, mlen) = abi.decode(orig, (uint256, uint256, address, uint256, uint256, uint256, address, address, uint256, uint256, uint256));
        message = new bytes(mlen);
        for (uint256 i = 0; i < mlen; i++) {
            message[i] = orig[i + 352];
        }
    }

}
