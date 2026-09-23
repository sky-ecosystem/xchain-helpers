// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import { TargetContractMock } from "./mocks/TargetContractMock.sol";

import { CCTPv2Receiver } from "../src/receivers/CCTPv2Receiver.sol";

contract CCTPv2ReceiverTest is Test {

    TargetContractMock target;

    CCTPv2Receiver receiver;

    address destinationMessenger = makeAddr("destinationMessenger");
    uint32  sourceDomainId       = 1;
    bytes32 sourceAuthority      = bytes32(uint256(uint160(makeAddr("sourceAuthority"))));
    address randomAddress        = makeAddr("randomAddress");

    function setUp() public {
        target = new TargetContractMock();

        receiver = new CCTPv2Receiver({
            _destinationMessenger : destinationMessenger,
            _sourceDomainId       : sourceDomainId,
            _sourceAuthority      : sourceAuthority,
            _target               : address(target)
        });
    }

    function test_constructor() public {
        receiver = new CCTPv2Receiver({
            _destinationMessenger : destinationMessenger,
            _sourceDomainId       : sourceDomainId,
            _sourceAuthority      : sourceAuthority,
            _target               : address(target)
        });

        assertEq(receiver.destinationMessenger(), destinationMessenger);
        assertEq(receiver.sourceDomainId(),       sourceDomainId);
        assertEq(receiver.sourceAuthority(),      sourceAuthority);
        assertEq(receiver.target(),               address(target));
    }

    function test_receiveUnfinalizedMessage_revert() public {
        vm.prank(destinationMessenger);
        vm.expectRevert("CCTPv2Receiver/unfinalized-messages-not-accepted");
        receiver.handleReceiveUnfinalizedMessage({
            remoteDomain              : sourceDomainId,
            sender                    : sourceAuthority,
            finalityThresholdExecuted : 0,
            messageBody               : abi.encodeCall(TargetContractMock.increment, ())
        });
    }

    function test_handleReceiveFinalizedMessage_invalidSender() public {
        vm.prank(randomAddress);
        vm.expectRevert("CCTPv2Receiver/invalid-sender");
        receiver.handleReceiveFinalizedMessage({
            remoteDomain              : sourceDomainId,
            sender                    : sourceAuthority,
            finalityThresholdExecuted : 0,
            messageBody               : abi.encodeCall(TargetContractMock.increment, ())
        });
    }

    function test_handleReceiveFinalizedMessage_invalidSourceChainId() public {
        vm.prank(destinationMessenger);
        vm.expectRevert("CCTPv2Receiver/invalid-sourceDomain");
        receiver.handleReceiveFinalizedMessage({
            remoteDomain              : 2,
            sender                    : sourceAuthority,
            finalityThresholdExecuted : 0,
            messageBody               : abi.encodeCall(TargetContractMock.increment, ())
        });
    }

    function test_handleReceiveFinalizedMessage_invalidSourceAuthority() public {
        vm.prank(destinationMessenger);
        vm.expectRevert("CCTPv2Receiver/invalid-sourceAuthority");
        receiver.handleReceiveFinalizedMessage({
            remoteDomain              : sourceDomainId,
            sender                    : bytes32(uint256(uint160(randomAddress))),
            finalityThresholdExecuted : 0,
            messageBody               : abi.encodeCall(TargetContractMock.increment, ())
        });
    }

    function test_handleReceiveFinalizedMessage_success() public {
        assertEq(target.count(), 0);

        vm.prank(destinationMessenger);
        receiver.handleReceiveFinalizedMessage({
            remoteDomain              : sourceDomainId,
            sender                    : sourceAuthority,
            finalityThresholdExecuted : 0,
            messageBody               : abi.encodeCall(TargetContractMock.increment, ())
        });

        assertEq(target.count(), 1);
    }

    function test_handleReceiveFinalizedMessage_revert() public {
        vm.prank(destinationMessenger);
        vm.expectRevert("TargetContract/error");
        receiver.handleReceiveFinalizedMessage({
            remoteDomain              : sourceDomainId,
            sender                    : sourceAuthority,
            finalityThresholdExecuted : 0,
            messageBody               : abi.encodeCall(TargetContractMock.revertFunc, ())
        });
    }

}
