// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Domain } from "./Domain.sol";

enum BridgeType {
    OPTIMISM,
    ARBITRUM,
    CCTP,
    AMB,
    LZ,
    CCTP_V2
}

struct Bridge {
    BridgeType bridgeType;
    Domain     source;
    Domain     destination;
    address    sourceCrossChainMessenger;
    address    destinationCrossChainMessenger;
    // These are used internally for log tracking
    uint256 lastSourceLogIndex;
    uint256 lastDestinationLogIndex;
    bytes   extraData;
}
