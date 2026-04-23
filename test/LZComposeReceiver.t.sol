// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import { TargetContractMock } from "test/mocks/TargetContractMock.sol";

import { LZForwarder }                    from "src/forwarders/LZForwarder.sol";
import { LZComposeReceiver, Origin }      from "src/receivers/LZComposeReceiver.sol";
interface ILayerZeroEndpointV2 {
    event ComposeSent(address from, address to, bytes32 guid, uint16 index, bytes message);
    function delegates(address sender) external view returns (address);
    function composeQueue(address _from, address _to, bytes32 _guid, uint16 _index) external view returns (bytes32);
    function lzCompose(
        address _from,
        address _to,
        bytes32 _guid,
        uint16  _index,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable;
}

contract LZComposeReceiverTest is Test {

    TargetContractMock target;

    LZComposeReceiver receiver;

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

        receiver = new LZComposeReceiver(
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

    // --- lzReceive tests ---

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
        vm.expectRevert("LZComposeReceiver/invalid-srcEid");
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
        vm.expectRevert("LZComposeReceiver/invalid-sourceAuthority");
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

    function test_lzReceive_invalidValue() public {
        vm.deal(destinationEndpoint, 1 ether);
        vm.prank(destinationEndpoint);
        vm.expectRevert("LZComposeReceiver/invalid-value");
        receiver.lzReceive{ value: 1 ether }(
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
    }

    function test_lzReceive_success() public {
        bytes32 guid    = keccak256("test-guid");
        bytes memory msg_ = abi.encodeCall(TargetContractMock.increment, ());

        vm.prank(destinationEndpoint);
        vm.expectEmit(destinationEndpoint);
        emit ILayerZeroEndpointV2.ComposeSent(address(receiver), address(receiver), guid, 0, msg_);
        receiver.lzReceive(
            Origin({
                srcEid: srcEid,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            guid,
            msg_,
            address(0),
            ""
        );

        // Target should NOT have been called yet (deferred to lzCompose)
        assertEq(target.count(), 0);

        // Compose queue should have the message hash stored
        bytes32 queuedHash = ILayerZeroEndpointV2(destinationEndpoint).composeQueue(
            address(receiver), address(receiver), guid, 0
        );
        assertEq(queuedHash, keccak256(msg_));
    }

    // --- lzCompose tests ---

    function test_lzCompose_invalidSender() public {
        vm.prank(randomAddress);
        vm.expectRevert("LZComposeReceiver/only-endpoint");
        receiver.lzCompose(
            address(receiver),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
    }

    function test_lzCompose_invalidFrom() public {
        vm.prank(destinationEndpoint);
        vm.expectRevert("LZComposeReceiver/invalid-from");
        receiver.lzCompose(
            randomAddress,
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
    }

    function test_lzCompose_targetRevert() public {
        vm.prank(destinationEndpoint);
        vm.expectRevert("TargetContract/error");
        receiver.lzCompose(
            address(receiver),
            bytes32(0),
            abi.encodeCall(TargetContractMock.revertFunc, ()),
            address(0),
            ""
        );
    }

    function test_lzCompose_success() public {
        assertEq(target.count(), 0);

        vm.prank(destinationEndpoint);
        receiver.lzCompose(
            address(receiver),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );

        assertEq(target.count(), 1);
    }

    function test_lzCompose_successWithValue() public {
        uint256 value = 1 ether;
        vm.deal(destinationEndpoint, value);

        assertEq(target.count(), 0);
        assertEq(address(target).balance, 0);

        vm.prank(destinationEndpoint);
        receiver.lzCompose{ value: value }(
            address(receiver),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );

        assertEq(target.count(), 1);
        assertEq(address(target).balance, value);
    }

    // --- lzReceive followed by lzCompose ---

    function test_lzReceive_lzCompose() public {
        bytes32 guid    = keccak256("test-guid-2");
        bytes memory msg_ = abi.encodeCall(TargetContractMock.increment, ());

        assertEq(target.count(), 0);

        // Phase 1: lzReceive enqueues compose
        vm.prank(destinationEndpoint);
        receiver.lzReceive(
            Origin({
                srcEid: srcEid,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            guid,
            msg_,
            address(0),
            ""
        );

        assertEq(target.count(), 0);

        // Phase 2: Execute compose through the real endpoint
        ILayerZeroEndpointV2(destinationEndpoint).lzCompose(
            address(receiver),
            address(receiver),
            guid,
            0,
            msg_,
            ""
        );

        assertEq(target.count(), 1);
    }

    // --- allowInitializePath tests ---

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
