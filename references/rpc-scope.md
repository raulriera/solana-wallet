# RPC scope

Build for the agreed Simplified and Advanced wallet experiences. A test or hypothetical future use alone doesn't justify an RPC method.

Connect directly to interchangeable Solana RPC providers; no app-owned backend or proxy. `HeliusRPC` and public-endpoint `Solana` share one internal HTTP client. Keep provider-specific endpoints, authentication, and extensions inside RPC; consumers depend on provider-neutral protocols. DAS serves portfolio viewing only; see [portfolio](portfolio.md). App workflow coordination follows [architecture](architecture.md).

| Feature | RPC need |
| --- | --- |
| Create/import seed phrases; view/copy address | None. Keep these local. |
| View portfolio | DAS through `GetAssetsByOwner`, including native SOL, asset metadata, and available prices. |
| V1 transactions | Ordered instruction compositions: blockhash and expiry, fee/resource estimates, simulation, submission, and signature status. Token transfers use `GetMultipleAccounts` for mint/account state, `GetEpochInfo` for Token-2022 fee schedules, and `GetMinimumBalanceForRentExemption` for new destination deposits. |
| AI-enhanced transaction simulation | Reuse simulation results, logs, and errors for human-readable explanations in a separate framework after RPC; see [simulation explanations](transaction-simulation.md). |

- Confidential transfers remain conditional; agree on feasibility and the concrete flow before adding support.
- Account and rent reads serve token-transfer prerequisites; general account exploration and node-version queries remain outside the current scope.
- RPC completion means the agreed flows have the communication they need. Human-readable simulation explanations remain a separate milestone; AI exploration is parked. UI remains last.
- Public Solana mainnet (`https://api.mainnet.solana.com`) is built in. Submission chooses ordinary RPC broadcast or one Helius Sender tier, never both; see [submission policy](transaction-workflow.md#submission-and-observation).

## Rate limits

- Keep requests single-attempt. Expose HTTP `429` through `RPCError.http(statusCode:retryAfter:)`, preserving the sanitized `Retry-After` header. No shared rate limiter, cooldown, or automatic retries.
- Consumers decide presentation and recovery. Portfolio keeps its cached snapshot and exposes the refresh error; the app may silently ignore the warning.
- Preserve each provider's submission error. Multi-submit attempts each enabled route once; one provider's rate limit must not cancel the others. Do not automatically resubmit.

## Verification

September 28, 2026:

- RPC: 52 tests passed. App transaction workflows: 44 tests passed; the mainnet Sender delivery test was skipped. Real Helius and public Solana clients confirmed SOL and wrapped-SOL transfers through both token programs, checked balances through both providers, and returned funds and temporary account deposits after fees. Missing token accounts and unfunded-payer rejection also passed.
- Additional actual-client reads verified current blockhash validity, block height, epoch and account responses through both devnet providers, plus Helius DAS with native balance. Mainnet account-based priority-fee estimation succeeded as a read-only request.
- Provider limitation: Helius devnet returned `-32601` for `getPriorityFeeEstimate`. Mainnet rejected both a fresh unsigned V1 transaction and an independently signed Kit V1 fixture with `-32602`, although account-based estimates worked. Transaction-based V1 estimates remain unverified as a supported capability; do not add an automatic fallback. See [Helius's API contract](https://www.helius.dev/docs/api-reference/priority-fee/getpriorityfeeestimate).
- The live devnet rejection exposed an error-handling defect: a null response identifier hid the server error behind a decoding error. The client now preserves sanitized null-ID server errors, requires matching IDs for successful results and attributed errors, and still rejects missing or malformed ID fields. No retries or submission behavior changed.
