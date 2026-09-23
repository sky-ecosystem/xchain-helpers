// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./IntegrationBase.t.sol";

import { CCTPv2BridgeTesting } from "src/testing/bridges/CCTPv2BridgeTesting.sol";
import { CCTPv2Forwarder }     from "src/forwarders/CCTPv2Forwarder.sol";
import { CCTPv2Receiver }      from "src/receivers/CCTPv2Receiver.sol";

contract DummyReceiver {

    bytes public message;

    function handleReceiveFinalizedMessage(
        uint32       /*remoteDomain*/,
        bytes32      /*sender*/,
        uint32       /*finalityThresholdExecuted*/,
        bytes memory messageBody
    ) external returns (bool) {
        message = messageBody;
        return true;
    }

}

contract CircleCCTPv2IntegrationTest is IntegrationBaseTest {

    using CCTPv2BridgeTesting for *;
    using DomainHelpers       for *;

    uint32 sourceDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM;
    uint32 destinationDomainId;

    Domain destination2;
    Bridge bridge2;

    function _addressToCctpBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    // Use Arbitrum One for failure tests as the code logic is the same

    function test_invalidSender() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE;
        initBaseContracts(getChain("arbitrum_one").createFork());

        destination.selectFork();

        vm.prank(randomAddress);
        vm.expectRevert("CCTPv2Receiver/invalid-sender");
        CCTPv2Receiver(destinationReceiver).handleReceiveFinalizedMessage({
            remoteDomain              : sourceDomainId,
            sender                    : _addressToCctpBytes32(sourceAuthority),
            finalityThresholdExecuted : 2000,
            messageBody               : abi.encodeCall(MessageOrdering.push, (1))
        });
    }

    function test_invalidSourceDomain() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE;
        initBaseContracts(getChain("arbitrum_one").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert("CCTPv2Receiver/invalid-sourceDomain");
        CCTPv2Receiver(destinationReceiver).handleReceiveFinalizedMessage({
            remoteDomain              : 1,
            sender                    : _addressToCctpBytes32(sourceAuthority),
            finalityThresholdExecuted : 2000,
            messageBody               : abi.encodeCall(MessageOrdering.push, (1))
        });
    }

    function test_invalidSourceAuthority() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE;
        initBaseContracts(getChain("arbitrum_one").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert("CCTPv2Receiver/invalid-sourceAuthority");
        CCTPv2Receiver(destinationReceiver).handleReceiveFinalizedMessage({
            remoteDomain              : sourceDomainId,
            sender                    : _addressToCctpBytes32(randomAddress),
            finalityThresholdExecuted : 2000,
            messageBody               : abi.encodeCall(MessageOrdering.push, (1))
        });
    }

    function test_optimism() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_OPTIMISM;
        runCrossChainTests(getChain("optimism").createFork());
    }

    function test_arbitrum_one() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE;
        runCrossChainTests(getChain("arbitrum_one").createFork());
    }

    function test_base() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE;
        runCrossChainTests(getChain("base").createFork());
    }

    function test_unichain() public {
        setChain("unichain", ChainData({
            name: "Unichain",
            rpcUrl: vm.envString("UNICHAIN_RPC_URL"),
            chainId: 130
        }));

        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_UNICHAIN;
        runCrossChainTests(getChain("unichain").createFork());
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

        bridge  = CCTPv2BridgeTesting.createCircleBridge(source, destination);
        bridge2 = CCTPv2BridgeTesting.createCircleBridge(source, destination2);

        source.selectFork();

        CCTPv2Forwarder.sendMessage({
            messageTransmitter  : CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ETHEREUM,
            destinationDomainId : CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            recipient           : address(r1),
            messageBody         : abi.encode(1)
        });
        CCTPv2Forwarder.sendMessage({
            messageTransmitter  : CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ETHEREUM,
            destinationDomainId : CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE,
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
        CCTPv2Forwarder.sendMessage({
            messageTransmitter  : CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_BASE,
            destinationDomainId : CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            recipient           : address(r0),
            messageBody         : abi.encode(3)
        });

        destination2.selectFork();
        CCTPv2Forwarder.sendMessage({
            messageTransmitter  : CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ARBITRUM_ONE,
            destinationDomainId : CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            recipient           : address(r0),
            messageBody         : abi.encode(4)
        });
        CCTPv2Forwarder.sendMessage({
            messageTransmitter  : CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ARBITRUM_ONE,
            destinationDomainId : CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
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
            new CCTPv2Receiver({
                _destinationMessenger : bridge.sourceCrossChainMessenger,
                _sourceDomainId       : destinationDomainId,
                _sourceAuthority      : _addressToCctpBytes32(destinationAuthority),
                _target               : address(moSource)
            })
        );
    }

    function initDestinationReceiver() internal override returns (address) {
        return address(
            new CCTPv2Receiver({
                _destinationMessenger : bridge.destinationCrossChainMessenger,
                _sourceDomainId       : sourceDomainId,
                _sourceAuthority      : _addressToCctpBytes32(sourceAuthority),
                _target               : address(moDestination)
            })
        );
    }

    function initBridgeTesting() internal override returns (Bridge memory) {
        return CCTPv2BridgeTesting.createCircleBridge(source, destination);
    }

    function queueSourceToDestination(bytes memory message) internal override {
        CCTPv2Forwarder.sendMessage({
            messageTransmitter  : bridge.sourceCrossChainMessenger,
            destinationDomainId : destinationDomainId,
            recipient           : destinationReceiver,
            messageBody         : message
        });
    }

    function queueDestinationToSource(bytes memory message) internal override {
        CCTPv2Forwarder.sendMessage({
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
