// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./IntegrationBase.t.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { Origin }         from "layerzerolabs/oapp-evm/contracts/oapp/OAppReceiver.sol";

import { LZBridgeTesting }                     from "src/testing/bridges/LZBridgeTesting.sol";
import { LZForwarder }                         from "src/forwarders/LZForwarder.sol";
import { LZGovBridgeForwarder, MessagingFee }  from "src/forwarders/LZGovBridgeForwarder.sol";
import { LZGovBridgeReceiver }                 from "src/receivers/LZGovBridgeReceiver.sol";

import { GovernanceOAppReceiverMock } from "test/mocks/lz/GovernanceOAppReceiverMock.sol";

interface IGovOappSender {
    function owner() external view returns (address);
    function setPeer(uint32 _eid, bytes32 _peer) external;
    function setCanCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget, bool _canCall) external;
    function canCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget) external view returns (bool);
}

contract LZGovBridgeIntegrationTest is IntegrationBaseTest {

    using DomainHelpers   for *;
    using LZBridgeTesting for *;
    using OptionsBuilder  for bytes;

    address constant GOV_OAPP_SENDER = 0x27FC1DD771817b53bE48Dc28789533BEa53C9CCA;

    uint32 sourceEndpointId = LZForwarder.ENDPOINT_ID_ETHEREUM;
    uint32 destinationEndpointId;

    address sourceEndpoint = LZForwarder.ENDPOINT_ETHEREUM;
    address destinationEndpoint;

    GovernanceOAppReceiverMock govReceiver;
    LZGovBridgeReceiver        govBridgeReceiver;

    error NoPeer(uint32 eid);
    error OnlyEndpoint(address addr);
    error OnlyPeer(uint32 eid, bytes32 sender);

    function test_invalidEndpoint() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(OnlyEndpoint.selector, randomAddress));
        GovernanceOAppReceiverMock(destinationReceiver).lzReceive(
            Origin({
                srcEid: sourceEndpointId,
                sender: bytes32(uint256(uint160(GOV_OAPP_SENDER))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodePacked(bytes32(uint256(uint160(address(this)))), bytes32(uint256(uint160(address(moDestination)))), abi.encodeCall(MessageOrdering.push, (1))),
            address(0),
            ""
        );
    }

    function test_lzReceive_revertsNoPeer() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert(abi.encodeWithSelector(NoPeer.selector, 0));
        GovernanceOAppReceiverMock(destinationReceiver).lzReceive(
            Origin({
                srcEid: 0,
                sender: bytes32(uint256(uint160(GOV_OAPP_SENDER))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodePacked(bytes32(uint256(uint160(address(this)))), bytes32(uint256(uint160(address(moDestination)))), abi.encodeCall(MessageOrdering.push, (1))),
            address(0),
            ""
        );
    }

    function test_lzReceive_revertsOnlyPeer() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert(abi.encodeWithSelector(OnlyPeer.selector, sourceEndpointId, bytes32(uint256(uint160(randomAddress)))));
        GovernanceOAppReceiverMock(destinationReceiver).lzReceive(
            Origin({
                srcEid: sourceEndpointId,
                sender: bytes32(uint256(uint160(randomAddress))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodePacked(bytes32(uint256(uint160(address(this)))), bytes32(uint256(uint160(address(moDestination)))), abi.encodeCall(MessageOrdering.push, (1))),
            address(0),
            ""
        );
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
        address govOwner = IGovOappSender(GOV_OAPP_SENDER).owner();
        vm.startPrank(govOwner);
        IGovOappSender(GOV_OAPP_SENDER).setPeer(
            destinationEndpointId,
            bytes32(uint256(uint160(destinationReceiver)))
        );
        IGovOappSender(GOV_OAPP_SENDER).setCanCallTarget(
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

        // Send one more to ensure subsequent calls don't repeat
        source.selectFork();
        _sendGovBridgeMessage(abi.encodeCall(MessageOrdering.push, (3)));

        relaySourceToDestination();

        assertEq(moDestination.length(), 3);
        assertEq(moDestination.messages(2), 3);
    }

    function _sendGovBridgeMessage(bytes memory message) internal {
        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        MessagingFee memory fee = LZGovBridgeForwarder.quote(
            GOV_OAPP_SENDER,
            destinationEndpointId,
            address(govBridgeReceiver),
            message,
            extraOptions,
            false
        );

        vm.deal(address(this), fee.nativeFee);
        LZGovBridgeForwarder.sendMessage(
            GOV_OAPP_SENDER,
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
        govReceiver = new GovernanceOAppReceiverMock(
            sourceEndpointId,
            bytes32(uint256(uint160(GOV_OAPP_SENDER))),
            destinationEndpoint,
            address(this)
        );
        govBridgeReceiver = new LZGovBridgeReceiver(
            address(govReceiver),
            sourceEndpointId,
            address(this),         // srcAuthority: the test contract calls sendTx
            address(moDestination)
        );
        return address(govReceiver);
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
        bridge.relayMessagesToDestination(true, GOV_OAPP_SENDER, destinationReceiver);
    }

    function relayDestinationToSource() internal pure override {
        revert("not supported");
    }

}
