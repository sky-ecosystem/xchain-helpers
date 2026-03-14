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

    error NoPeer(uint32 eid);
    error OnlyEndpoint(address addr);
    error OnlyPeer(uint32 eid, bytes32 sender);

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
    }

    function test_constructor() public view {
        assertEq(receiver.srcEid(),          srcEid);
        assertEq(receiver.sourceAuthority(), bytes32(uint256(uint160(sourceAuthority))));
        assertEq(receiver.target(),          address(target));
        assertEq(receiver.owner(),           owner);
        assertEq(receiver.peers(srcEid),     bytes32(uint256(uint160(sourceAuthority))));

        assertEq(
            ILayerZeroEndpointV2(address(receiver.endpoint())).delegates(address(receiver)),
            delegate
        );
    }

    function test_invalidEndpoint() public {
        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(OnlyEndpoint.selector, randomAddress));
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

    function test_lzReceive_revertsNoPeer() public {
        vm.prank(destinationEndpoint);
        vm.expectRevert(abi.encodeWithSelector(NoPeer.selector, 0));
        receiver.lzReceive(
            Origin({
                srcEid: 0,
                sender: bytes32(uint256(uint160(randomAddress))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
    }

    function test_lzReceive_revertsOnlyPeer() public {
        vm.prank(destinationEndpoint);
        vm.expectRevert(abi.encodeWithSelector(OnlyPeer.selector, srcEid, bytes32(uint256(uint160(randomAddress)))));
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

    function test_lzReceive_invalidSrcEid() public {
        // NOTE: To pass initial check, we set the peer.
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
        // NOTE: To pass initial check, we set the peer.
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

    function test_allowInitializePath() public {
        // Should return true when origin.srcEid == srcEid, origin.sender == sourceAuthority and peers[origin.srcEid] == origin.sender
        assertTrue(receiver.allowInitializePath(Origin({
            srcEid: srcEid,
            sender: bytes32(uint256(uint160(sourceAuthority))),
            nonce:  1
        })));

        // Should return false when peers[origin.srcEid] != origin.sender

        assertFalse(receiver.allowInitializePath(Origin({
            srcEid: srcEid,
            sender: bytes32(uint256(uint160(randomAddress))),
            nonce:  1
        })));

        // Should return false when origin.srcEid != srcEid

        // NOTE: Setting peer to make `super.allowInitializePath(origin)` return true
        vm.prank(owner);
        receiver.setPeer(srcEid + 1, bytes32(uint256(uint160(sourceAuthority))));

        assertFalse(receiver.allowInitializePath(Origin({
            srcEid: srcEid + 1,
            sender: bytes32(uint256(uint160(sourceAuthority))),
            nonce:  1
        })));

        // Should return false when origin.sender != sourceAuthority

        // NOTE: Setting peer to make `super.allowInitializePath(origin)` return true
        vm.prank(owner);
        receiver.setPeer(srcEid, bytes32(uint256(uint160(randomAddress))));

        assertFalse(receiver.allowInitializePath(Origin({
            srcEid: srcEid,
            sender: bytes32(uint256(uint160(randomAddress))),
            nonce:  1
        })));
    }

}
