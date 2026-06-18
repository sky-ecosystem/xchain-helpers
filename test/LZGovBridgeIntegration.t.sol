// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { Bridge }                from "src/testing/Bridge.sol";
import { Domain, DomainHelpers } from "src/testing/Domain.sol";
import { LZBridgeTesting }      from "src/testing/bridges/LZBridgeTesting.sol";

import { LZGovBridgeForwarder, MessagingFee } from "src/forwarders/LZGovBridgeForwarder.sol";
import { LZGovBridgeReceiver }                from "src/receivers/LZGovBridgeReceiver.sol";

import { GovernanceOAppReceiverMock } from "test/mocks/lz/GovernanceOAppReceiverMock.sol";
import { MessageOrdering }           from "test/IntegrationBase.t.sol";

interface IChainLog {
    function getAddress(bytes32) external view returns (address);
}

interface IGovOappSender {
    function owner() external view returns (address);
    function setPeer(uint32 _eid, bytes32 _peer) external;
    function setCanCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget, bool _canCall) external;
}

// NOTE: Does not inherit IntegrationBaseTest because the LZ gov bridge is unidirectional
// (source -> destination only) and requires existing on-chain infrastructure
// (GovernanceOAppSender) that doesn't fit the bidirectional runCrossChainTests pattern.
contract LZGovBridgeIntegrationTest is Test {

    using DomainHelpers   for *;
    using LZBridgeTesting for *;
    using OptionsBuilder  for bytes;

    uint32  constant ENDPOINT_ID_BASE = 30184;
    uint32  constant ENDPOINT_ID_BNB  = 30102;
    address constant ENDPOINT_BASE    = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant ENDPOINT_BNB     = 0x1a44076050125825900e736c501f859c50fE728c;

    IChainLog constant chainlog = IChainLog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    address sourceAuthority = makeAddr("sourceAuthority");

    Domain source;
    Domain destination;

    MessageOrdering moDestination;

    Bridge bridge;

    address govOappSender;

    uint32 sourceEndpointId = LZGovBridgeForwarder.ENDPOINT_ID_ETHEREUM;
    uint32 destinationEndpointId;
    address destinationEndpoint;

    GovernanceOAppReceiverMock govOappReceiver;
    LZGovBridgeReceiver        govBridgeReceiver;

    function setUp() public {
        source = getChain("mainnet").createFork();
        source.selectFork();
        govOappSender = chainlog.getAddress("LZ_GOV_SENDER");
    }

    function test_base() public {
        destinationEndpointId = ENDPOINT_ID_BASE;
        destinationEndpoint   = ENDPOINT_BASE;

        _runGovBridgeTest(getChain("base").createFork());
    }

    function test_binance() public {
        destinationEndpointId = ENDPOINT_ID_BNB;
        destinationEndpoint   = ENDPOINT_BNB;

        _runGovBridgeTest(getChain("bnb_smart_chain").createFork());
    }

    function _runGovBridgeTest(Domain memory _destination) internal {
        destination = _destination;

        bridge = LZBridgeTesting.createLZBridge(source, destination);

        // Deploy destination contracts
        destination.selectFork();
        moDestination = new MessageOrdering();
        govOappReceiver = new GovernanceOAppReceiverMock(
            sourceEndpointId,
            bytes32(uint256(uint160(govOappSender))),
            destinationEndpoint,
            address(this)
        );
        govBridgeReceiver = new LZGovBridgeReceiver(
            address(govOappReceiver),
            sourceEndpointId,
            address(this),
            address(moDestination)
        );
        moDestination.setReceiver(address(govBridgeReceiver));

        // Configure the GovernanceOAppSender: set peer and grant permission
        source.selectFork();
        address govOwner = IGovOappSender(govOappSender).owner();
        vm.startPrank(govOwner);
        IGovOappSender(govOappSender).setPeer(
            destinationEndpointId,
            bytes32(uint256(uint160(address(govOappReceiver))))
        );
        IGovOappSender(govOappSender).setCanCallTarget(
            address(this),
            destinationEndpointId,
            bytes32(uint256(uint160(address(govBridgeReceiver)))),
            true
        );
        vm.stopPrank();

        // Send two messages source -> destination
        _sendGovBridgeMessage(abi.encodeCall(MessageOrdering.push, (1)));
        _sendGovBridgeMessage(abi.encodeCall(MessageOrdering.push, (2)));

        bridge.relayMessagesToDestination(true, govOappSender, address(govOappReceiver));

        assertEq(moDestination.length(), 2);
        assertEq(moDestination.messages(0), 1);
        assertEq(moDestination.messages(1), 2);

        // Send a message with ether value
        source.selectFork();
        _sendGovBridgeMessage(abi.encodeCall(MessageOrdering.push, (3)));

        uint256 value = 1 ether;
        vm.deal(address(this), value);
        bridge.relayMessagesToDestination(true, govOappSender, address(govOappReceiver), value);

        assertEq(moDestination.length(), 3);
        assertEq(moDestination.messages(2), 3);
        assertEq(address(moDestination).balance, value);
    }

    function _sendGovBridgeMessage(bytes memory message) internal {
        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        MessagingFee memory fee = LZGovBridgeForwarder.quote(
            govOappSender,
            destinationEndpointId,
            address(govBridgeReceiver),
            message,
            extraOptions,
            false
        );

        vm.deal(address(this), fee.nativeFee);
        LZGovBridgeForwarder.sendMessage(
            govOappSender,
            destinationEndpointId,
            address(govBridgeReceiver),
            message,
            extraOptions,
            sourceAuthority,
            fee,
            address(0)
        );
    }

}
