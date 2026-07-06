// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

interface ICrossDomainOptimism {
    function sendMessage(address _target, bytes calldata _message, uint32 _gasLimit) external;
}

library OptimismForwarder {

    address constant internal L1_CROSS_DOMAIN_BASE        = 0x866E82a600A1414e583f7F13623F1aC5d58b0Afa;
    address constant internal L1_CROSS_DOMAIN_OPTIMISM    = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;
    address constant internal L1_CROSS_DOMAIN_UNICHAIN    = 0x9A3D64E386C18Cb1d6d5179a9596A4B5736e98A6;
    address constant internal L1_CROSS_DOMAIN_WORLD_CHAIN = 0xf931a81D18B1766d15695ffc7c1920a62b7e710a;
    address constant internal L1_CROSS_DOMAIN_XLAYER      = 0xF94B553F3602a03931e5D10CaB343C0968D793e3;

    address constant internal L2_CROSS_DOMAIN             = 0x4200000000000000000000000000000000000007;

    function sendMessageL1toL2(
        address l1CrossDomain,
        address target,
        bytes memory message,
        uint32 gasLimit
    ) internal {
        ICrossDomainOptimism(l1CrossDomain).sendMessage(
            target,
            message,
            gasLimit
        );
    }

    function sendMessageL2toL1(
        address target,
        bytes memory message,
        uint32 gasLimit
    ) internal {
        ICrossDomainOptimism(L2_CROSS_DOMAIN).sendMessage(
            target,
            message,
            gasLimit
        );
    }

}
