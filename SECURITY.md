# Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/rockthecoin/contracts/security/advisories/new) for vulnerabilities in these contracts or in the RockTheCoin service. Include the network, contract address and version, affected function, expected impact and a reproducible example. Keep keys, seed phrases and customer data out of reports.

Please do not post an exploitable issue publicly before it has been assessed. Test only with assets you control and prefer local execution. This repository contains public deterministic fixture keys; they must never receive real funds.

## Scope and support

The [deployment map](deployments.json) identifies the versions used by the live service at the stated snapshot date. Historical packages remain available to inspect existing assets. Published bytecode is immutable; a correction requires a new version and a separate operator-approved deployment. Publishing a new package does not upgrade an existing deployment.

The included checks are maintained by the project. They are not an independent audit or a guarantee of security. No bug-bounty payout or response deadline is promised.

See [permissions and trust assumptions](docs/permissions.md), [version notes](docs/releases.md) and the live [Security & contracts page](https://www.rockthecoin.com/security).
