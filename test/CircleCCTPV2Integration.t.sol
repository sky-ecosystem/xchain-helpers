// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Address } from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

import "./IntegrationBase.t.sol";

import { CCTPV2BridgeTesting } from "src/testing/bridges/CCTPV2BridgeTesting.sol";

import { CCTPForwarder } from "src/forwarders/CCTPForwarder.sol";

// THESE CONTRACTS ARE USED TO TEST THE CCTPV2 BRIDGE AND HAVE NOT BEEN AUDITED.

interface IMessageTransmitterV2 {

    function sendMessage(
        uint32           destinationDomain,
        bytes32          recipient,
        bytes32          destinationCaller,     // 0x0 = anyone can relay
        uint32           minFinalityThreshold,  // 2000 = standard (finalized), 1000 = fast (unfinalized)
        bytes   calldata messageBody
    ) external;

}

library CCTPV2Forwarder {

    uint32 internal constant MIN_FINALITY_STANDARD = 2_000;

    bytes32 internal constant DESTINATION_CALLER_ANY = bytes32(0);

    function sendMessage(
        address        messageTransmitter,
        uint32         destinationDomainId,
        bytes32        recipient,
        bytes   memory messageBody
    ) internal {
        IMessageTransmitterV2(messageTransmitter).sendMessage(
            destinationDomainId,
            recipient,
            DESTINATION_CALLER_ANY,
            MIN_FINALITY_STANDARD,
            messageBody
        );
    }

    function sendMessage(
        address        messageTransmitter,
        uint32         destinationDomainId,
        address        recipient,
        bytes   memory messageBody
    ) internal {
        sendMessage(
            messageTransmitter,
            destinationDomainId,
            bytes32(uint256(uint160(recipient))),
            messageBody
        );
    }

}

contract DummyReceiver {

    bytes public message;

    function handleReceiveFinalizedMessage(
        uint32         /*remoteDomain*/,
        bytes32        /*sender*/,
        uint32         /*finalityThresholdExecuted*/,
        bytes   memory messageBody
    ) external returns (bool) {
        message = messageBody;
        return true;
    }

}

contract CCTPV2Receiver {

    using Address for address;

    address public immutable destinationMessenger;
    uint32  public immutable sourceDomainId;
    bytes32 public immutable sourceAuthority;
    address public immutable target;

    constructor(
        address _destinationMessenger,
        uint32  _sourceDomainId,
        bytes32 _sourceAuthority,
        address _target
    ) {
        destinationMessenger = _destinationMessenger;
        sourceDomainId       = _sourceDomainId;
        sourceAuthority      = _sourceAuthority;
        target               = _target;
    }

    /// @notice Finalized (standard finality) messages are accepted.
    function handleReceiveFinalizedMessage(
        uint32         remoteDomain,
        bytes32        sender,
        uint32         finalityThresholdExecuted,
        bytes   memory messageBody
    ) external returns (bool) {
        require(msg.sender   == destinationMessenger, "CCTPV2Receiver/invalid-sender");
        require(remoteDomain == sourceDomainId,       "CCTPV2Receiver/invalid-sourceDomain");
        require(sender       == sourceAuthority,      "CCTPV2Receiver/invalid-sourceAuthority");

        target.functionCall(messageBody);

        return true;
    }

    /// @notice Unfinalized (fast) messages are rejected by default.
    function handleReceiveUnfinalizedMessage(
        uint32         remoteDomain,
        bytes32        sender,
        uint32         finalityThresholdExecuted,
        bytes   memory messageBody
    ) external pure returns (bool) {
        revert("CCTPV2Receiver/unfinalized-messages-not-accepted");
    }

}

contract CircleCCTPV2IntegrationTest is IntegrationBaseTest {

    using CCTPV2BridgeTesting for *;
    using DomainHelpers       for *;

    uint32 sourceDomainId = CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM;
    uint32 destinationDomainId;

    Domain destination2;
    Bridge bridge2;

    function _addressToCctpBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    // Use Arbitrum One for failure tests as the code logic is the same

    function test_invalidSender() public {
        destinationDomainId = CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE;
        initBaseContracts(getChain("arbitrum_one").createFork());

        destination.selectFork();

        vm.prank(randomAddress);
        vm.expectRevert("CCTPV2Receiver/invalid-sender");
        CCTPV2Receiver(destinationReceiver).handleReceiveFinalizedMessage({
            remoteDomain              : sourceDomainId,
            sender                    : _addressToCctpBytes32(sourceAuthority),
            finalityThresholdExecuted : 2000,
            messageBody               : abi.encodeCall(MessageOrdering.push, (1))
        });
    }

    function test_invalidSourceDomain() public {
        destinationDomainId = CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE;
        initBaseContracts(getChain("arbitrum_one").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert("CCTPV2Receiver/invalid-sourceDomain");
        CCTPV2Receiver(destinationReceiver).handleReceiveFinalizedMessage({
            remoteDomain              : 1,
            sender                    : _addressToCctpBytes32(sourceAuthority),
            finalityThresholdExecuted : 2000,
            messageBody               : abi.encodeCall(MessageOrdering.push, (1))
        });
    }

    function test_invalidSourceAuthority() public {
        destinationDomainId = CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE;
        initBaseContracts(getChain("arbitrum_one").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert("CCTPV2Receiver/invalid-sourceAuthority");
        CCTPV2Receiver(destinationReceiver).handleReceiveFinalizedMessage({
            remoteDomain              : sourceDomainId,
            sender                    : _addressToCctpBytes32(randomAddress),
            finalityThresholdExecuted : 2000,
            messageBody               : abi.encodeCall(MessageOrdering.push, (1))
        });
    }

    function test_optimism() public {
        destinationDomainId = CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM;
        runCrossChainTests(getChain("optimism").createFork());
    }

    function test_arbitrum_one() public {
        destinationDomainId = CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE;
        runCrossChainTests(getChain("arbitrum_one").createFork());
    }

    function test_base() public {
        destinationDomainId = CCTPForwarder.DOMAIN_ID_CIRCLE_BASE;
        runCrossChainTests(getChain("base").createFork());
    }

    function test_unichain() public {
        setChain("unichain", ChainData({
            name: "Unichain",
            rpcUrl: vm.envString("UNICHAIN_RPC_URL"),
            chainId: 130
        }));

        destinationDomainId = CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN;
        runCrossChainTests(getChain("unichain").createFork());
    }

    function test_xlayer() public {
        setChain("xlayer", ChainData({
            name: "XLayer",
            rpcUrl: "https://rpc.xlayer.tech",
            chainId: 196
        }));

        destinationDomainId = 37;  // XLayer CCTPV2 domain ID
        runCrossChainTests(getChain("xlayer").createFork());
    }

    function test_multiple() public {
        destination  = getChain("base").createFork();
        destination2 = getChain("arbitrum_one").createFork();

        DummyReceiver r0 = new DummyReceiver();
        assertEq(r0.message().length, 0);

        destination.selectFork();
        DummyReceiver r1 = new DummyReceiver();
        assertEq(r1.message().length, 0);

        destination2.selectFork();
        DummyReceiver r2 = new DummyReceiver();
        assertEq(r2.message().length, 0);

        bridge  = CCTPV2BridgeTesting.createCircleBridge(source, destination);
        bridge2 = CCTPV2BridgeTesting.createCircleBridge(source, destination2);

        source.selectFork();

        CCTPV2Forwarder.sendMessage({
            messageTransmitter  : CCTPV2BridgeTesting.MESSAGE_TRANSMITTER_CIRCLE,
            destinationDomainId : CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            recipient           : address(r1),
            messageBody         : abi.encode(1)
        });
        CCTPV2Forwarder.sendMessage({
            messageTransmitter  : CCTPV2BridgeTesting.MESSAGE_TRANSMITTER_CIRCLE,
            destinationDomainId : CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE,
            recipient           : address(r2),
            messageBody         : abi.encode(2)
        });

        bridge.relayMessagesToDestination(true);
        bridge2.relayMessagesToDestination(true);

        destination.selectFork();
        assertEq(r1.message(), abi.encode(1));

        destination2.selectFork();
        assertEq(r2.message(), abi.encode(2));

        destination.selectFork();
        CCTPV2Forwarder.sendMessage({
            messageTransmitter  : CCTPV2BridgeTesting.MESSAGE_TRANSMITTER_CIRCLE,
            destinationDomainId : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            recipient           : address(r0),
            messageBody         : abi.encode(3)
        });

        destination2.selectFork();
        CCTPV2Forwarder.sendMessage({
            messageTransmitter  : CCTPV2BridgeTesting.MESSAGE_TRANSMITTER_CIRCLE,
            destinationDomainId : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            recipient           : address(r0),
            messageBody         : abi.encode(4)
        });
        CCTPV2Forwarder.sendMessage({
            messageTransmitter  : CCTPV2BridgeTesting.MESSAGE_TRANSMITTER_CIRCLE,
            destinationDomainId : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            recipient           : address(r0),
            messageBody         : abi.encode(5)
        });

        assertEq(r0.message(), bytes(""));

        bridge.relayMessagesToDestination(true);
        bridge2.relayMessagesToDestination(true);

        assertEq(r0.message(), bytes(""));

        bridge2.relayMessagesToSource(true);

        assertEq(r0.message(), abi.encode(5));

        bridge.relayMessagesToSource(true);

        assertEq(r0.message(), abi.encode(3));
    }

    function initSourceReceiver() internal override returns (address) {
        return address(
            new CCTPV2Receiver({
                _destinationMessenger : bridge.sourceCrossChainMessenger,
                _sourceDomainId       : destinationDomainId,
                _sourceAuthority      : _addressToCctpBytes32(destinationAuthority),
                _target               : address(moSource)
            })
        );
    }

    function initDestinationReceiver() internal override returns (address) {
        return address(
            new CCTPV2Receiver({
                _destinationMessenger : bridge.destinationCrossChainMessenger,
                _sourceDomainId       : sourceDomainId,
                _sourceAuthority      : _addressToCctpBytes32(sourceAuthority),
                _target               : address(moDestination)
            })
        );
    }

    function initBridgeTesting() internal override returns (Bridge memory) {
        return CCTPV2BridgeTesting.createCircleBridge(source, destination);
    }

    function queueSourceToDestination(bytes memory message) internal override {
        CCTPV2Forwarder.sendMessage({
            messageTransmitter  : bridge.sourceCrossChainMessenger,
            destinationDomainId : destinationDomainId,
            recipient           : destinationReceiver,
            messageBody         : message
        });
    }

    function queueDestinationToSource(bytes memory message) internal override {
        CCTPV2Forwarder.sendMessage({
            messageTransmitter  : bridge.destinationCrossChainMessenger,
            destinationDomainId : sourceDomainId,
            recipient           : sourceReceiver,
            messageBody         : message
        });
    }

    function relaySourceToDestination() internal override {
        bridge.relayMessagesToDestination(true);
    }

    function relayDestinationToSource() internal override {
        bridge.relayMessagesToSource(true);
    }

}
