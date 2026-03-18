// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

contract TargetContractMock {

    uint256 public count;

    function increment() external payable {
        count++;
    }

    function revertFunc() external pure {
        revert("TargetContract/error");
    }
    
}
