// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import "forge-std/Test.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { Bridge }                from "src/testing/Bridge.sol";
import { Domain, DomainHelpers } from "src/testing/Domain.sol";
import { LZBridgeTesting }      from "src/testing/bridges/LZBridgeTesting.sol";

import { LZGovBridgeForwarder, MessagingFee } from "src/forwarders/LZGovBridgeForwarder.sol";
import { LZGovBridgeReceiver }                from "src/receivers/LZGovBridgeReceiver.sol";

import { GovernanceOAppReceiverMock } from "test/mocks/lz/GovernanceOAppReceiverMock.sol";
import { MessageOrdering }           from "test/IntegrationBase.t.sol";

import { IChainLog, IGovOappSender } from "test/LZGovBridgeIntegration.t.sol";

interface ILayerZeroEndpointV2 {
    function setLzToken(address _lzToken) external;
}

interface ITreasury {
    function setLzTokenEnabled(bool _lzTokenEnabled) external;
    function setLzTokenFee(uint256 _lzTokenFee) external;
}

// NOTE: Does not inherit IntegrationBaseTest because the LZ gov bridge is unidirectional
// (source -> destination only) and requires existing on-chain infrastructure
// (GovernanceOAppSender) that doesn't fit the bidirectional runCrossChainTests pattern.
contract LZGovBridgeIntegrationTestWithLZToken is Test {

    using DomainHelpers   for *;
    using LZBridgeTesting for *;
    using OptionsBuilder  for bytes;

    uint32  constant ENDPOINT_ID_BASE  = 30184;
    uint32  constant ENDPOINT_ID_BNB   = 30102;
    address constant ENDPOINT_BASE     = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant ENDPOINT_BNB      = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant ENDPOINT_ETHEREUM = 0x1a44076050125825900e736c501f859c50fE728c;

    IChainLog constant chainlog = IChainLog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    address sourceAuthority = makeAddr("sourceAuthority");

    Domain source;
    Domain destination;

    MessageOrdering moDestination;

    Bridge bridge;

    address govOappSender;

    uint32 sourceEndpointId = LZGovBridgeForwarder.ENDPOINT_ID_ETHEREUM;
    uint32 destinationEndpointId;

    address destinationEndpoint;

    address lzToken  = 0x6985884C4392D348587B19cb9eAAf157F13271cd;
    address lzOwner  = 0xBe010A7e3686FdF65E93344ab664D065A0B02478;
    address treasury = 0x5ebB3f2feaA15271101a927869B3A56837e73056;

    GovernanceOAppReceiverMock govOappReceiver;
    LZGovBridgeReceiver        govBridgeReceiver;

    function setUp() public {
        source = getChain("mainnet").createFork();
        source.selectFork();

        govOappSender = chainlog.getAddress("LZ_GOV_SENDER");

        vm.startPrank(lzOwner);
        ILayerZeroEndpointV2(ENDPOINT_ETHEREUM).setLzToken(lzToken);
        ITreasury(treasury).setLzTokenEnabled(true);
        ITreasury(treasury).setLzTokenFee(1e18);
        vm.stopPrank();
    }

    function test_base() public {
        destinationEndpointId = ENDPOINT_ID_BASE;
        destinationEndpoint   = ENDPOINT_BASE;

        _runGovBridgeTest(getChain("base").createFork());
    }

    function test_binance() public {
        destinationEndpointId = ENDPOINT_ID_BNB;
        destinationEndpoint   = ENDPOINT_BNB;

        _runGovBridgeTest(getChain("bnb_smart_chain").createFork());
    }

    function _runGovBridgeTest(Domain memory _destination) internal {
        destination = _destination;

        bridge = LZBridgeTesting.createLZBridge(source, destination);

        // Deploy destination contracts
        destination.selectFork();
        moDestination = new MessageOrdering();
        govOappReceiver = new GovernanceOAppReceiverMock(
            sourceEndpointId,
            bytes32(uint256(uint160(govOappSender))),
            destinationEndpoint,
            address(this)
        );
        govBridgeReceiver = new LZGovBridgeReceiver(
            address(govOappReceiver),
            sourceEndpointId,
            address(this),
            address(moDestination)
        );
        moDestination.setReceiver(address(govBridgeReceiver));

        // Configure the GovernanceOAppSender: set peer and grant permission
        source.selectFork();
        address govOwner = IGovOappSender(govOappSender).owner();
        vm.startPrank(govOwner);
        IGovOappSender(govOappSender).setPeer(
            destinationEndpointId,
            bytes32(uint256(uint160(address(govOappReceiver))))
        );
        IGovOappSender(govOappSender).setCanCallTarget(
            address(this),
            destinationEndpointId,
            bytes32(uint256(uint160(address(govBridgeReceiver)))),
            true
        );
        vm.stopPrank();

        // Send message with LZ token payment
        _sendGovBridgeMessage(abi.encodeCall(MessageOrdering.push, (1)));

        bridge.relayMessagesToDestination(true, govOappSender, address(govOappReceiver));

        assertEq(moDestination.length(), 1);
        assertEq(moDestination.messages(0), 1);
    }

    function _sendGovBridgeMessage(bytes memory message) internal {
        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        MessagingFee memory fee = LZGovBridgeForwarder.quote(
            govOappSender,
            destinationEndpointId,
            address(govBridgeReceiver),
            message,
            extraOptions,
            true
        );

        assertGt(fee.nativeFee,  0);
        assertGt(fee.lzTokenFee, 0);

        vm.deal(address(this), fee.nativeFee);
        deal(lzToken, address(this), fee.lzTokenFee);

        LZGovBridgeForwarder.sendMessage(
            govOappSender,
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

}
