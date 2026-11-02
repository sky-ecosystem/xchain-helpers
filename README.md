# xchain-helpers

This repository has three tools for use with multi-chain development. Domains refer to blockchains which are connected by bridges. Domains may have multiple bridges connecting them, for example both the Optimism Native Bridge and Circle CCTP connect Ethereum and Optimism domains.

## Forwarders

These libraries provide standardized syntax for sending a message to a bridge.

## Receivers

![xchain-helpers](.assets/xchain-helpers.png)

The most common pattern is to have an authorized contract forward a message to another "business logic" contract to abstract away bridge dependencies. Receivers are contracts which perform this generic translation - decoding the bridge-specific message and forwarding to another `target` contract. The `target` contract should have logic to restrict who can call it and permission this to one or more bridge receivers.

Most receivers implement a `fallback()` function which after validating that the call came from an authorized party on the other side of the bridge will forward the call to the `target` contract with the same function signature. This separation of concerns makes it easy for the receiver contract to focus on validating the bridge message, and the business logic `target` contract can validate the `msg.sender` comes from the receiver which validates the whole process. This ensures no chain-specific code is required for the business logic contract.

## E2E Testing Infrastructure

Provides tooling to record messages sent to supported bridges and relay them on the other side simulating a real message going across.

## Audits

Audit reports are hosted on the auditors' public portfolio pages:

| Auditor | Report | Version | Date |
| --- | --- | --- | --- |
| ChainSecurity | [Sky xchain-helpers](https://www.chainsecurity.com/security-audit/sky-xchain-helpers/) | v1.2.0 | 2026-08-21 |
| Cantina | [Sky: Stars LZ Governance](https://cantina.xyz/portfolio/3369b702-f6e2-4c17-b6e1-1ff34953e68a) | - | 2026-08-19 |
| ChainSecurity | [SparkDAO xchain-helpers](https://www.chainsecurity.com/security-audit/spark-xchain-helpers/) | v1.0.0, v1.1.0 | 2025-10-08 |
| Cantina | [xchain-helpers; spark-gov-relay](https://cantina.xyz/portfolio/854c4127-0cdc-4712-be6b-60d0c01f1a54) | v1.0.0 | 2024-08-20 |

ChainSecurity reports are cumulative: each portfolio page hosts the latest version of the report, which covers all previously reviewed versions.

### Other reports

The following reports are not available on an auditor portfolio page and are kept in this repository:

- [Cantina v1.1.0](./audits/v110-cantina-audit.pdf)
- [Cantina v1.2.0](./audits/v120-cantina-audit.pdf)
