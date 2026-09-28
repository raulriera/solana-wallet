# RPC scope

Build for the agreed Simplified and Advanced wallet experiences. A test or hypothetical future use alone doesn't justify an RPC method.

Connect directly to interchangeable Solana RPC providers; no app-owned backend or proxy. `HeliusRPC` and public-endpoint `Solana` share one internal HTTP client. Keep provider-specific endpoints, authentication, and extensions inside RPC; consumers depend on provider-neutral protocols. DAS serves portfolio viewing only; see [portfolio](portfolio.md). App workflow coordination follows [architecture](architecture.md).

| Feature | RPC need |
| --- | --- |
| Create/import seed phrases; view/copy address | None. Keep these local. |
| View portfolio | DAS through `GetAssetsByOwner`, including native SOL, asset metadata, and available prices. |
| V1 transactions | Blockhash and expiry, fee estimates, simulation, submission, and signature status. Token transfers also use `GetMultipleAccounts` for mint/account state and `GetEpochInfo` for Token-2022 fee schedules. |
| AI-enhanced transaction simulation | Reuse simulation results, logs, and errors for human-readable explanations in a separate framework after RPC; see [simulation explanations](transaction-simulation.md). |

- Confidential transfers remain conditional; agree on feasibility and the concrete flow before adding support.
- Account reads serve token-transfer prerequisites; general account exploration, rent-exemption, and node-version queries remain outside the current scope.
- RPC completion means the agreed flows have the communication they need. Human-readable simulation explanations remain a separate milestone; AI exploration is parked. UI remains last.
- Public Solana mainnet (`https://api.mainnet.solana.com`) is built in. App submission filters configured providers by activation and network, then broadcasts concurrently. Optional Helius Sender remains next; see [submission policy](transfers.md#submission-policy).

## Rate limits

- Keep requests single-attempt. Expose HTTP `429` through `RPCError.http(statusCode:retryAfter:)`, preserving the sanitized `Retry-After` header. No shared rate limiter, cooldown, or automatic retries.
- Consumers decide presentation and recovery. Portfolio keeps its cached snapshot and exposes the refresh error; the app may silently ignore the warning.
- Preserve each provider's submission error. Multi-submit attempts each enabled route once; one provider's rate limit must not cancel the others. Do not automatically resubmit.
