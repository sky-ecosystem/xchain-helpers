// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { Address } from "openzeppelin-contracts/contracts/utils/Address.sol";

struct MessageOrigin {
    uint32  srcEid;
    bytes32 srcSender;
}

interface IGovernanceOAppReceiver {
    function messageOrigin() external view returns (MessageOrigin memory);
}

/**
 * @title  LZGovBridgeReceiver
 * @notice Receive messages via the Sky LZ governance bridge.
 */
contract LZGovBridgeReceiver {

    using Address for address;

    address public immutable govOappReceiver;
    uint32  public immutable srcEid;
    address public immutable srcAuthority;
    address public immutable target;

    constructor(
        address _govOappReceiver,
        uint32  _srcEid,
        address _srcAuthority,
        address _target
    ) {
        govOappReceiver = _govOappReceiver;
        srcEid          = _srcEid;
        srcAuthority    = _srcAuthority; // The forwarder on the calling side
        target          = _target;
    }

    fallback(bytes calldata message) external payable returns (bytes memory) {
        require(msg.sender == govOappReceiver, "LZGovBridgeReceiver/invalid-sender");

        MessageOrigin memory origin = IGovernanceOAppReceiver(govOappReceiver).messageOrigin();
        require(origin.srcEid == srcEid,                                     "LZGovBridgeReceiver/invalid-srcEid");
        require(address(uint160(uint256(origin.srcSender))) == srcAuthority, "LZGovBridgeReceiver/invalid-srcAuthority");

        return target.functionCallWithValue(message, msg.value);
    }

}
