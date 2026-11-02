# Contributing

Open an issue for non-sensitive suggestions or a pull request with a focused change and relevant validation. Use private vulnerability reporting for security issues.

Do not change a published source file, standard compiler input, ABI or artifact in place. Propose a new version and add regression coverage. Do not include credentials, deployment keys, environment files or personal data.

Run `npm ci --ignore-scripts`, `npm run verify:integrity`, `npm run verify:builds`, and `npm test`. For Solana program execution, install `requirements-test.txt` in a Python virtual environment and run `python tests/solana_controller.py`.

Repository tests execute in memory and do not use funded wallets or broadcast transactions. On-chain read scripts are separate, explicit commands.
