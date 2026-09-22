// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

import { Address } from "openzeppelin-contracts/contracts/utils/Address.sol";

/**
 * @title  CCTPv2Receiver
 * @notice Receive messages from CCTPv2-style bridge.
 */
contract CCTPv2Receiver {

    using Address for address;

    address public immutable destinationMessenger;
    uint32  public immutable sourceDomainId;
    bytes32 public immutable sourceAuthority;
    address public immutable target;

    constructor(
        address _destinationMessenger,
        uint32  _sourceDomainId,
        bytes32 _sourceAuthority,
        address _target
    ) {
        destinationMessenger = _destinationMessenger;
        sourceDomainId       = _sourceDomainId;
        sourceAuthority      = _sourceAuthority;
        target               = _target;
    }

    /// @notice Finalized (standard finality) messages are accepted.
    function handleReceiveFinalizedMessage(
        uint32  remoteDomain,
        bytes32 sender,
        uint32  /*finalityThresholdExecuted*/,
        bytes   memory messageBody
    ) external returns (bool) {
        require(msg.sender   == destinationMessenger, "CCTPv2Receiver/invalid-sender");
        require(remoteDomain == sourceDomainId,       "CCTPv2Receiver/invalid-sourceDomain");
        require(sender       == sourceAuthority,      "CCTPv2Receiver/invalid-sourceAuthority");

        target.functionCall(messageBody);

        return true;
    }

    /// @notice Unfinalized (fast) messages are rejected by default.
    function handleReceiveUnfinalizedMessage(
        uint32  /*remoteDomain*/,
        bytes32 /*sender*/,
        uint32  /*finalityThresholdExecuted*/,
        bytes   memory /*messageBody*/
    ) external pure returns (bool) {
        revert("CCTPv2Receiver/unfinalized-messages-not-accepted");
    }

}
