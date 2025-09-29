// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import { Bridge }                from "src/testing/Bridge.sol";
import { Domain, DomainHelpers } from "src/testing/Domain.sol";

contract MessageOrdering {

    address   public receiver;
    uint256[] public messages;

    function push(uint256 messageId) external {
        // Null receiver means there is no code for this path so we ignore the check
        require(receiver == address(0) || msg.sender == receiver, "only-receiver");

        messages.push(messageId);
    }

    function length() public view returns (uint256) {
        return messages.length;
    }

    function setReceiver(address _receiver) external {
        receiver = _receiver;
    }

}

abstract contract IntegrationBaseTest is Test {

    using DomainHelpers for *;

    address sourceAuthority      = makeAddr("sourceAuthority");
    address destinationAuthority = makeAddr("destinationAuthority");
    address randomAddress        = makeAddr("randomAddress");

    Domain source;
    Domain destination;

    MessageOrdering moSource;
    MessageOrdering moDestination;

    address sourceReceiver;
    address destinationReceiver;

    Bridge bridge;

    function setUp() public virtual {
        source = getChain("mainnet").createFork();
    }

    function initBaseContracts(Domain memory _destination) internal virtual {
        destination = _destination;

        bridge = initBridgeTesting();

        source.selectFork();
        moSource = new MessageOrdering();
        sourceReceiver = initSourceReceiver();
        moSource.setReceiver(sourceReceiver);

        destination.selectFork();
        moDestination = new MessageOrdering();
        destinationReceiver = initDestinationReceiver();
        moDestination.setReceiver(destinationReceiver);

        // Default to source fork as it's an obvious default
        source.selectFork();
    }

    function runCrossChainTests(Domain memory _destination) internal {
        initBaseContracts(_destination);

        destination.selectFork();

        // Queue up some Destination -> Source messages
        vm.startPrank(destinationAuthority);
        queueDestinationToSource(abi.encodeCall(MessageOrdering.push, (3)));
        queueDestinationToSource(abi.encodeCall(MessageOrdering.push, (4)));
        vm.stopPrank();

        assertEq(moDestination.length(), 0);

        // Do not relay right away
        source.selectFork();

        // Queue up two more Source -> Destination messages
        vm.startPrank(sourceAuthority);
        queueSourceToDestination(abi.encodeCall(MessageOrdering.push, (1)));
        queueSourceToDestination(abi.encodeCall(MessageOrdering.push, (2)));
        vm.stopPrank();

        assertEq(moSource.length(), 0);

        relaySourceToDestination();

        assertEq(moDestination.length(), 2);
        assertEq(moDestination.messages(0), 1);
        assertEq(moDestination.messages(1), 2);

        relayDestinationToSource();

        assertEq(moSource.length(), 2);
        assertEq(moSource.messages(0), 3);
        assertEq(moSource.messages(1), 4);

        // Do one more message both ways to ensure subsequent calls don't repeat already sent messages
        vm.startPrank(sourceAuthority);
        queueSourceToDestination(abi.encodeCall(MessageOrdering.push, (5)));
        vm.stopPrank();

        relaySourceToDestination();

        assertEq(moDestination.length(), 3);
        assertEq(moDestination.messages(2), 5);

        vm.startPrank(destinationAuthority);
        queueDestinationToSource(abi.encodeCall(MessageOrdering.push, (6)));
        vm.stopPrank();

        relayDestinationToSource();

        assertEq(moSource.length(), 3);
        assertEq(moSource.messages(2), 6);
    }

    function initSourceReceiver() internal virtual returns (address);
    function initDestinationReceiver() internal virtual returns (address);
    function initBridgeTesting() internal virtual returns (Bridge memory);
    function queueSourceToDestination(bytes memory message) internal virtual;
    function queueDestinationToSource(bytes memory message) internal virtual;
    function relaySourceToDestination() internal virtual;
    function relayDestinationToSource() internal virtual;

}
