// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { LZBridgeTesting }                   from "src/testing/bridges/LZBridgeTesting.sol";
import { LZForwarder, ILayerZeroEndpointV2 } from "src/forwarders/LZForwarder.sol";
import { LZReceiver, Origin }                from "src/receivers/LZReceiver.sol";
import { RecordedLogs }                      from "src/testing/utils/RecordedLogs.sol";

import "./IntegrationBase.t.sol";

interface ITreasury {
    function setLzTokenEnabled(bool _lzTokenEnabled) external;
    function setLzTokenFee(uint256 _lzTokenFee) external;
}

contract LZIntegrationTestWithLZToken is IntegrationBaseTest {

    using DomainHelpers   for *;
    using LZBridgeTesting for *;
    using OptionsBuilder  for bytes;

    uint32 sourceEndpointId = LZForwarder.ENDPOINT_ID_ETHEREUM;
    uint32 destinationEndpointId;

    address sourceEndpoint = LZForwarder.ENDPOINT_ETHEREUM;
    address destinationEndpoint;

    address lzToken  = 0x6985884C4392D348587B19cb9eAAf157F13271cd;
    address lzOwner  = 0xBe010A7e3686FdF65E93344ab664D065A0B02478;
    address treasury = 0x5ebB3f2feaA15271101a927869B3A56837e73056;

    Domain destination2;
    Bridge bridge2;

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

        runCrossChainTests(getChain("base").createFork());
    }

    function test_binance() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BNB;
        destinationEndpoint   = LZForwarder.ENDPOINT_BNB;

        runCrossChainTests(getChain("bnb_smart_chain").createFork());
    }

    function initSourceReceiver() internal override returns (address) {
        return address(new LZReceiver(
            sourceEndpoint,
            destinationEndpointId,
            bytes32(uint256(uint160(destinationAuthority))),
            address(moSource),
            makeAddr("delegate"),
            makeAddr("owner")
        ));
    }

    function initDestinationReceiver() internal override returns (address) {
        return address(new LZReceiver(
            destinationEndpoint,
            sourceEndpointId,
            bytes32(uint256(uint160(sourceAuthority))),
            address(moDestination),
            makeAddr("delegate"),
            makeAddr("owner")
        ));
    }

    function initBridgeTesting() internal override returns (Bridge memory) {
        return LZBridgeTesting.createLZBridge(source, destination);
    }

    function queueSourceToDestination(bytes memory message) internal override {
        // Gas to queue message
        vm.deal(sourceAuthority, 1 ether);
        deal(lzToken, sourceAuthority, 1 ether);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        assertEq(IERC20(lzToken).balanceOf(address(sourceAuthority)), 1 ether);
        assertEq(address(sourceAuthority).balance,                    1 ether);

        LZForwarder.sendMessage(
            destinationEndpointId,
            bytes32(uint256(uint160(destinationReceiver))),
            ILayerZeroEndpointV2(bridge.sourceCrossChainMessenger),
            message,
            options,
            sourceAuthority,
            true
        );

        // LZ token and ETH spent
        assertLt(IERC20(lzToken).balanceOf(address(sourceAuthority)), 1 ether);
        assertLt(address(sourceAuthority).balance,                    1 ether);
    }

    function queueDestinationToSource(bytes memory message) internal override {
        vm.deal(destinationAuthority, 1 ether); // Gas to queue message

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        LZForwarder.sendMessage(
            sourceEndpointId,
            bytes32(uint256(uint160(sourceReceiver))),
            ILayerZeroEndpointV2(bridge.destinationCrossChainMessenger),
            message,
            options,
            destinationAuthority,
            false
        );
    }

    function relaySourceToDestination() internal override {
        bridge.relayMessagesToDestination(true, sourceAuthority, destinationReceiver);
    }

    function relayDestinationToSource() internal override {
        bridge.relayMessagesToSource(true, destinationAuthority, sourceReceiver);
    }

}
