# RPC scope

Build for the agreed Simplified and Advanced wallet experiences. A test or hypothetical future use alone doesn't justify an RPC method.

Connect directly to interchangeable Solana RPC providers; no app-owned backend or proxy. `HeliusRPC` and public-endpoint `Solana` share one internal HTTP client. Keep provider-specific endpoints, authentication, and extensions inside RPC; consumers depend on provider-neutral protocols. DAS serves portfolio viewing only; see [portfolio](portfolio.md). App workflow coordination follows [architecture](architecture.md).

| Feature | RPC need |
| --- | --- |
| Create/import seed phrases; view/copy address | None. Keep these local. |
| Discover accounts after phrase import | One `GetMultipleAccounts` request for twenty public addresses; keep positive SOL balances and ignore zero-SOL accounts. [Wallet](wallet.md) defines the bounded scan. |
| View portfolio | DAS through `GetAssetsByOwner`, including native SOL, asset metadata, and available prices. |
| V1 transactions | Ordered instruction compositions: blockhash and expiry, fee/resource estimates, simulation, submission, and signature status. Token transfers use `GetMultipleAccounts` for mint/account state, `GetEpochInfo` for Token-2022 fee schedules, and `GetMinimumBalanceForRentExemption` for new destination deposits. |
| AI-enhanced transaction simulation | Reuse simulation results, logs, and errors for human-readable explanations in a separate framework after RPC; see [simulation explanations](transaction-simulation.md). |

- Confidential transfers remain conditional; agree on feasibility and the concrete flow before adding support.
- Account and rent reads serve token-transfer prerequisites and the agreed SOL-only account-discovery flow; general account exploration and node-version queries remain outside the current scope. Token ownership and address-history methods have no current agreed consumer and are not exposed.
- RPC completion means the agreed flows have the communication they need. Human-readable simulation explanations remain a separate milestone; AI exploration is parked. UI remains last.
- Public Solana mainnet (`https://api.mainnet.solana.com`) is built in. Submission chooses ordinary RPC broadcast or one Helius Sender tier, never both; see [submission policy](transaction-workflow.md#submission-and-observation).
- Preserve sanitized server errors with null response IDs. Successful results and attributed errors require matching IDs; missing or malformed ID fields are rejected.

## Rate limits

- Keep requests single-attempt. Expose HTTP `429` through `RPCError.http(statusCode:retryAfter:)`, preserving the sanitized `Retry-After` header. No shared rate limiter, cooldown, or automatic retries.
- Consumers decide presentation and recovery. Portfolio keeps its cached snapshot and exposes the refresh error; the app may silently ignore the warning.
- Preserve each provider's submission error. Multi-submit attempts each enabled route once; one provider's rate limit must not cancel the others. Do not automatically resubmit.

## Provider limitations

Helius priority-fee estimation is verified only for account-based mainnet requests. Devnet and transaction-based V1 estimates are not verified as supported capabilities; do not add an automatic fallback. See [Helius's API contract](https://www.helius.dev/docs/api-reference/priority-fee/getpriorityfeeestimate).
