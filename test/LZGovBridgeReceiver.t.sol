// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import { TargetContractMock }         from "test/mocks/TargetContractMock.sol";
import { GovernanceOAppReceiverMock } from "test/mocks/lz/GovernanceOAppReceiverMock.sol";
import { EndpointMock }               from "test/mocks/lz/EndpointMock.sol";
import { LZGovBridgeReceiver }        from "src/receivers/LZGovBridgeReceiver.sol";

contract LZGovBridgeReceiverTest is Test {

    TargetContractMock         target;
    GovernanceOAppReceiverMock govOappReceiver;
    LZGovBridgeReceiver        receiver;

    address randomAddress  = makeAddr("randomAddress");
    address srcAuthority   = makeAddr("srcAuthority");

    uint32 srcEid = 30101; // endpoint id on ethereum

    function setUp() public {
        target          = new TargetContractMock();
        govOappReceiver = new GovernanceOAppReceiverMock(
            srcEid,
            bytes32(uint256(uint160(srcAuthority))),
            address(new EndpointMock()),
            address(this)
        );

        receiver = new LZGovBridgeReceiver(
            address(govOappReceiver),
            srcEid,
            srcAuthority,
            address(target)
        );
    }

    function test_constructor() public view {
        assertEq(receiver.govOappReceiver(), address(govOappReceiver));
        assertEq(receiver.srcEid(),          srcEid);
        assertEq(receiver.srcAuthority(),    srcAuthority);
        assertEq(receiver.target(),          address(target));
    }

    function test_invalidSender() public {
        vm.prank(randomAddress);
        vm.expectRevert("LZGovBridgeReceiver/invalid-sender");
        TargetContractMock(address(receiver)).increment();
    }

    function test_invalidSrcEid() public {
        govOappReceiver.setMessageOrigin(srcEid + 1, bytes32(uint256(uint160(srcAuthority))));

        vm.prank(address(govOappReceiver));
        vm.expectRevert("LZGovBridgeReceiver/invalid-srcEid");
        TargetContractMock(address(receiver)).increment();
    }

    function test_invalidSrcAuthority() public {
        govOappReceiver.setMessageOrigin(srcEid, bytes32(uint256(uint160(randomAddress))));

        vm.prank(address(govOappReceiver));
        vm.expectRevert("LZGovBridgeReceiver/invalid-srcAuthority");
        TargetContractMock(address(receiver)).increment();
    }

    function test_success() public {
        govOappReceiver.setMessageOrigin(srcEid, bytes32(uint256(uint160(srcAuthority))));

        assertEq(target.count(), 0);

        vm.prank(address(govOappReceiver));
        TargetContractMock(address(receiver)).increment();

        assertEq(target.count(), 1);
    }

    function test_successWithValue() public {
        govOappReceiver.setMessageOrigin(srcEid, bytes32(uint256(uint160(srcAuthority))));

        uint256 value = 1 ether;
        vm.deal(address(govOappReceiver), value);

        assertEq(target.count(), 0);
        assertEq(address(target).balance, 0);

        vm.prank(address(govOappReceiver));
        TargetContractMock(address(receiver)).increment{value: value}();

        assertEq(target.count(), 1);
        assertEq(address(target).balance, value);
    }

    function test_receiveRevertsOnPlainEthTransfer() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert("LZGovBridgeReceiver/not-supported");
        (bool success,) = address(receiver).call{value: 1 ether}("");
        success;
    }

    function test_targetRevert() public {
        govOappReceiver.setMessageOrigin(srcEid, bytes32(uint256(uint160(srcAuthority))));

        vm.prank(address(govOappReceiver));
        vm.expectRevert("TargetContract/error");
        TargetContractMock(address(receiver)).revertFunc();
    }

}
