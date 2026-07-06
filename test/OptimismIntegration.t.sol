// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./IntegrationBase.t.sol";

import { OptimismBridgeTesting } from "src/testing/bridges/OptimismBridgeTesting.sol";
import { OptimismForwarder }     from "src/forwarders/OptimismForwarder.sol";
import { OptimismReceiver }      from "src/receivers/OptimismReceiver.sol";

contract OptimismIntegrationTest is IntegrationBaseTest {

    using OptimismBridgeTesting for *;
    using DomainHelpers         for *;

    event FailedRelayedMessage(bytes32);

    // Use Optimism mainnet for failure test as the code logic is the same

    function test_invalidSender() public {
        initBaseContracts(getChain("optimism").createFork());

        destination.selectFork();

        vm.prank(randomAddress);
        vm.expectRevert("OptimismReceiver/invalid-sender");
        MessageOrdering(destinationReceiver).push(1);
    }

    function test_invalidSourceAuthority() public {
        initBaseContracts(getChain("optimism").createFork());

        vm.startPrank(randomAddress);
        queueSourceToDestination(abi.encodeCall(MessageOrdering.push, (1)));
        vm.stopPrank();

        // The revert is caught so it doesn't propagate
        // Just look at the no change to verify it didn't go through
        relaySourceToDestination();
        assertEq(moDestination.length(), 0);
    }

    function test_optimism() public {
        runCrossChainTests(getChain("optimism").createFork());
    }

    function test_base() public {
        runCrossChainTests(getChain("base").createFork());
    }

    function test_world_chain() public {
        setChain("world_chain", ChainData({
            name: "World Chain",
            rpcUrl: vm.envString("WORLD_CHAIN_RPC_URL"),
            chainId: 480
        }));
        runCrossChainTests(getChain("world_chain").createFork());
    }

    function test_unichain() public {
        setChain("unichain", ChainData({
            name: "Unichain",
            rpcUrl: vm.envString("UNICHAIN_RPC_URL"),
            chainId: 130
        }));
        runCrossChainTests(getChain("unichain").createFork());
    }

    function test_xlayer() public {
        setChain("xlayer", ChainData({
            name: "XLayer",
            rpcUrl: "https://rpc.xlayer.tech",
            chainId: 196
        }));
        runCrossChainTests(getChain("xlayer").createFork());
    }

    function initSourceReceiver() internal override pure returns (address) {
        return address(0);
    }

    function initDestinationReceiver() internal override returns (address) {
        return address(new OptimismReceiver(sourceAuthority, address(moDestination)));
    }

    function initBridgeTesting() internal override returns (Bridge memory) {
        return OptimismBridgeTesting.createNativeBridge(source, destination);
    }

    function queueSourceToDestination(bytes memory message) internal override {
        OptimismForwarder.sendMessageL1toL2(
            bridge.sourceCrossChainMessenger,
            destinationReceiver,
            message,
            100000
        );
    }

    function queueDestinationToSource(bytes memory message) internal override {
        OptimismForwarder.sendMessageL2toL1(
            address(moSource),  // No receiver so send directly to the message ordering contract
            message,
            100000
        );
    }

    function relaySourceToDestination() internal override {
        bridge.relayMessagesToDestination(true);
    }

    function relayDestinationToSource() internal override {
        bridge.relayMessagesToSource(true);
    }

}
