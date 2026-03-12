// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import "./IntegrationBase.t.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { LZBridgeTesting }                     from "src/testing/bridges/LZBridgeTesting.sol";
import { LZForwarder, ILayerZeroEndpointV2 }   from "src/forwarders/LZForwarder.sol";
import { LZGovBridgeForwarder, MessagingFee }  from "src/forwarders/LZGovBridgeForwarder.sol";
import { LZGovBridgeReceiver }                 from "src/receivers/LZGovBridgeReceiver.sol";

import { GovernanceOAppReceiverMock } from "test/mocks/lz/GovernanceOAppReceiverMock.sol";

interface IGovOappSenderLzToken {
    function owner() external view returns (address);
    function setPeer(uint32 _eid, bytes32 _peer) external;
    function setCanCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget, bool _canCall) external;
}

interface ITreasury {
    function setLzTokenEnabled(bool _lzTokenEnabled) external;
    function setLzTokenFee(uint256 _lzTokenFee) external;
}

contract LZGovBridgeIntegrationTestWithLZToken is IntegrationBaseTest {

    using DomainHelpers   for *;
    using LZBridgeTesting for *;
    using OptionsBuilder  for bytes;

    address constant GOV_OAPP_SENDER = 0x27FC1DD771817b53bE48Dc28789533BEa53C9CCA;

    uint32 sourceEndpointId = LZForwarder.ENDPOINT_ID_ETHEREUM;
    uint32 destinationEndpointId;

    address sourceEndpoint = LZForwarder.ENDPOINT_ETHEREUM;
    address destinationEndpoint;

    address lzToken  = 0x6985884C4392D348587B19cb9eAAf157F13271cd;
    address lzOwner  = 0xBe010A7e3686FdF65E93344ab664D065A0B02478;
    address treasury = 0x5ebB3f2feaA15271101a927869B3A56837e73056;

    GovernanceOAppReceiverMock govReceiver;
    LZGovBridgeReceiver        govBridgeReceiver;

    function setUp() public override {
        super.setUp();

        source.selectFork();

        vm.startPrank(lzOwner);
        ILayerZeroEndpointV2(sourceEndpoint).setLzToken(lzToken);
        ITreasury(treasury).setLzTokenEnabled(true);
        ITreasury(treasury).setLzTokenFee(1e18);
        vm.stopPrank();
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
        address govOwner = IGovOappSenderLzToken(GOV_OAPP_SENDER).owner();
        vm.startPrank(govOwner);
        IGovOappSenderLzToken(GOV_OAPP_SENDER).setPeer(
            destinationEndpointId,
            bytes32(uint256(uint160(destinationReceiver)))
        );
        IGovOappSenderLzToken(GOV_OAPP_SENDER).setCanCallTarget(
            address(this),
            destinationEndpointId,
            bytes32(uint256(uint160(address(govBridgeReceiver)))),
            true
        );
        vm.stopPrank();

        // Send message with LZ token payment
        _sendGovBridgeMessage(abi.encodeCall(MessageOrdering.push, (1)));

        relaySourceToDestination();

        assertEq(moDestination.length(), 1);
        assertEq(moDestination.messages(0), 1);
    }

    function _sendGovBridgeMessage(bytes memory message) internal {
        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        MessagingFee memory fee = LZGovBridgeForwarder.quote(
            GOV_OAPP_SENDER,
            destinationEndpointId,
            address(govBridgeReceiver),
            message,
            extraOptions,
            true
        );

        vm.deal(address(this), fee.nativeFee);
        deal(lzToken, address(this), fee.lzTokenFee);

        assertEq(IERC20(lzToken).balanceOf(address(this)), fee.lzTokenFee);
        assertEq(address(this).balance,                     fee.nativeFee);

        LZGovBridgeForwarder.sendMessage(
            GOV_OAPP_SENDER,
            destinationEndpointId,
            address(govBridgeReceiver),
            message,
            extraOptions,
            sourceAuthority,
            fee,
            lzToken
        );

        // LZ token and ETH spent
        assertLt(IERC20(lzToken).balanceOf(address(this)), fee.lzTokenFee);
        assertLt(address(this).balance,                     fee.nativeFee);
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
            address(this),
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
