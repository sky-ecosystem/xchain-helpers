// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import { TargetContractMock } from "test/mocks/TargetContractMock.sol";

import { LZForwarder }        from "src/forwarders/LZForwarder.sol";
import { LZReceiver, Origin } from "src/receivers/LZReceiver.sol";

interface ILayerZeroEndpointV2 {
    function delegates(address sender) external view returns (address);
}

contract LZReceiverTest is Test {

    TargetContractMock target;

    LZReceiver receiver;

    address destinationEndpoint = LZForwarder.ENDPOINT_BNB;
    address randomAddress       = makeAddr("randomAddress");
    address sourceAuthority     = makeAddr("sourceAuthority");
    address delegate            = makeAddr("delegate");
    address owner               = makeAddr("owner");

    uint32 srcEid = LZForwarder.ENDPOINT_ID_ETHEREUM;

    function setUp() public {
        vm.createSelectFork(getChain("bnb_smart_chain").rpcUrl);

        target = new TargetContractMock();

        receiver = new LZReceiver(
            destinationEndpoint,
            srcEid,
            bytes32(uint256(uint160(sourceAuthority))),
            address(target),
            delegate,
            owner
        );

        vm.prank(owner);
        receiver.setPeer(srcEid, bytes32(uint256(uint160(sourceAuthority))));
    }

    function test_constructor() public view {
        assertEq(receiver.srcEid(),          srcEid);
        assertEq(receiver.sourceAuthority(), bytes32(uint256(uint160(sourceAuthority))));
        assertEq(receiver.target(),          address(target));
        assertEq(receiver.owner(),           owner);

        assertEq(
            ILayerZeroEndpointV2(address(receiver.endpoint())).delegates(address(receiver)),
            delegate
        );
    }

    function test_lzReceive_invalidSrcEid() public {
        vm.prank(owner);
        receiver.setPeer(srcEid + 1, bytes32(uint256(uint160(sourceAuthority))));

        vm.prank(destinationEndpoint);
        vm.expectRevert("LZReceiver/invalid-srcEid");
        receiver.lzReceive(
            Origin({
                srcEid: srcEid + 1,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
    }

    function test_lzReceive_invalidSourceAuthority() public {
        vm.prank(owner);
        receiver.setPeer(srcEid, bytes32(uint256(uint160(randomAddress))));

        vm.prank(destinationEndpoint);
        vm.expectRevert("LZReceiver/invalid-sourceAuthority");
        receiver.lzReceive(
            Origin({
                srcEid: srcEid,
                sender: bytes32(uint256(uint160(randomAddress))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
    }

    function test_lzReceive_success() public {
        assertEq(target.count(), 0);
        vm.prank(destinationEndpoint);
        receiver.lzReceive(
            Origin({
                srcEid: srcEid,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
        assertEq(target.count(), 1);
    }

}
