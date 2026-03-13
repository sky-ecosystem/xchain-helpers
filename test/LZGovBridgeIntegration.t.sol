// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./IntegrationBase.t.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { LZBridgeTesting }                     from "src/testing/bridges/LZBridgeTesting.sol";
import { LZForwarder }                         from "src/forwarders/LZForwarder.sol";
import { LZGovBridgeForwarder, MessagingFee }  from "src/forwarders/LZGovBridgeForwarder.sol";
import { LZGovBridgeReceiver }                 from "src/receivers/LZGovBridgeReceiver.sol";

import { GovernanceOAppReceiverMock } from "test/mocks/lz/GovernanceOAppReceiverMock.sol";

interface IChainLog {
    function getAddress(bytes32) external view returns (address);
}

interface IGovOappSender {
    function owner() external view returns (address);
    function setPeer(uint32 _eid, bytes32 _peer) external;
    function setCanCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget, bool _canCall) external;
}

contract LZGovBridgeIntegrationTest is IntegrationBaseTest {

    using DomainHelpers   for *;
    using LZBridgeTesting for *;
    using OptionsBuilder  for bytes;

    IChainLog constant chainlog = IChainLog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    address govOappSender;

    uint32 sourceEndpointId = LZForwarder.ENDPOINT_ID_ETHEREUM;
    uint32 destinationEndpointId;
    address destinationEndpoint;

    GovernanceOAppReceiverMock govOappReceiver;
    LZGovBridgeReceiver        govBridgeReceiver;

    function setUp() public override {
        super.setUp();
        source.selectFork();
        govOappSender = chainlog.getAddress("LZ_GOV_SENDER");
    }

    function test_base() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;

        _runGovBridgeTest(getChain("base").createFork());
    }

    function test_binance() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BNB;
        destinationEndpoint   = LZForwarder.ENDPOINT_BNB;

        _runGovBridgeTest(getChain("bnb_smart_chain").createFork());
    }

    function _runGovBridgeTest(Domain memory _destination) internal {
        initBaseContracts(_destination);

        // Allow LZGovBridgeReceiver to call moDestination
        destination.selectFork();
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

        relaySourceToDestination();

        assertEq(moDestination.length(), 2);
        assertEq(moDestination.messages(0), 1);
        assertEq(moDestination.messages(1), 2);
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

    // --- IntegrationBaseTest overrides ---

    function initDestinationReceiver() internal override returns (address) {
        govOappReceiver = new GovernanceOAppReceiverMock(
            sourceEndpointId,
            bytes32(uint256(uint160(govOappSender))),
            destinationEndpoint,
            address(this)
        );
        govBridgeReceiver = new LZGovBridgeReceiver(
            address(govOappReceiver),
            sourceEndpointId,
            address(this),         // srcAuthority: the test contract calls sendTx on govOappSender
            address(moDestination)
        );
        return address(govOappReceiver);
    }

    function initSourceReceiver() internal override returns (address) {
        return address(0);
    }

    function initBridgeTesting() internal override returns (Bridge memory) {
        return LZBridgeTesting.createLZBridge(source, destination);
    }

    function queueSourceToDestination(bytes memory) internal pure override {
        revert("not supported");
    }

    function queueDestinationToSource(bytes memory) internal pure override {
        revert("not supported");
    }

    function relaySourceToDestination() internal override {
        bridge.relayMessagesToDestination(true, govOappSender, address(govOappReceiver));
    }

    function relayDestinationToSource() internal pure override {
        revert("not supported");
    }

}
