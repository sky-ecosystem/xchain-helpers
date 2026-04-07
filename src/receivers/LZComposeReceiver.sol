// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { Address } from "openzeppelin-contracts/contracts/utils/Address.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";

import { OAppReceiver, Origin, OAppCore } from "layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { ILayerZeroComposer }             from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";

/**
 * @title  LZComposeReceiver
 * @notice Receive messages from LayerZero using the compose pattern.
 */
contract LZComposeReceiver is OAppReceiver, ILayerZeroComposer {

    using Address for address;

    address public immutable target;

    uint32  public immutable srcEid;

    bytes32 public immutable sourceAuthority;

    constructor(
        address _destinationEndpoint,
        uint32  _srcEid,
        bytes32 _sourceAuthority,
        address _target,
        address _delegate,
        address _owner
    ) OAppCore(_destinationEndpoint, _delegate) Ownable(_owner) {
        target          = _target;
        sourceAuthority = _sourceAuthority;
        srcEid          = _srcEid;

        _setPeer(_srcEid, _sourceAuthority);
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address,  // _executor
        bytes calldata  // _extraData
    ) internal override {
        require(_origin.srcEid == srcEid,          "LZComposeReceiver/invalid-srcEid");
        require(_origin.sender == sourceAuthority, "LZComposeReceiver/invalid-sourceAuthority");

        endpoint.sendCompose(address(this), _guid, 0, _message);
    }

    function lzCompose(
        address _from,
        bytes32,  // _guid
        bytes calldata _message,
        address,  // _executor
        bytes calldata  // _extraData
    ) external payable override {
        require(msg.sender == address(endpoint), "LZComposeReceiver/only-endpoint");
        require(_from == address(this),          "LZComposeReceiver/invalid-from");

        target.functionCallWithValue(_message, msg.value);
    }

    function allowInitializePath(Origin calldata origin) public view override returns (bool) {
        return super.allowInitializePath(origin)
            && origin.srcEid == srcEid
            && origin.sender == sourceAuthority;
    }

}
