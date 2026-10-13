# RPC scope

Build for the agreed Simplified and Advanced wallet experiences. A test or hypothetical future use alone doesn't justify an RPC method.

Connect directly to interchangeable RPC, DAS, and pricing providers; no app-owned backend or proxy. `HeliusRPC` and `Solana`, at a public or custom endpoint, share one internal HTTP client. Keep provider-specific endpoints, authentication, batching, and response transformations inside RPC; consumers depend on provider-neutral protocols and values. DAS serves only CDN logo lookups; see [portfolio](portfolio.md). App workflow coordination follows [architecture](architecture.md).

| Feature | RPC need |
| --- | --- |
| Create/import seed phrases; view/copy address | None. Keep these local. |
| Discover accounts after phrase import | One `GetMultipleAccounts` request for twenty public addresses; keep positive SOL balances and ignore zero-SOL accounts. [Wallet](wallet.md) defines the bounded scan. |
| View portfolio | One `GetMultipleAccounts` request reads native SOL and the listed tokens' accounts, at most 100 accounts. With Helius, DAS lookups of the listed mints supply CDN logos. |
| Add a token | One `GetMultipleAccounts` request reads the pasted mint and its Metaplex metadata account. With Helius, a DAS lookup adds the logo. |
| Add a custom RPC | One `GetMultipleAccounts` request, then acknowledged subscriptions over WSS at the same URL: `accountSubscribe`, and `signatureSubscribe` with `rootSubscribe` for a signature that no transaction carries. They confirm that the RPC serves the wallet and its payment watch before it is saved. |
| Observe incoming portfolio changes | `accountSubscribe` on the wallet and each listed token account supplies finalized changes; the portfolio then reads balances again. Notifications do not patch balances. |
| Update market prices independently | `PriceProviding` returns our `Quote` values keyed by mint. `Jupiter` implements it through Price V3; consumers can switch providers without adopting a provider's response shape. Price requests do not refetch holdings or metadata. |
| V1 transactions | Ordered instruction compositions: blockhash and its last valid block height, fee/resource estimates, simulation, submission, and a watch that reports a transaction as dropped once its blockhash expires without it landing. Token transfers use `GetMultipleAccounts` for mint/account state, `GetEpochInfo` for Token-2022 fee schedules, and `GetMinimumBalanceForRentExemption` for new destination deposits. |
| Watch a sent transaction | `signatureSubscribe` gives the result; `rootSubscribe` schedules checks; both share one WSS connection. `GetEpochInfo` at `finalized` proves expiry; until it does, one runs alongside the status read after each subscription. `GetSignatureStatuses` runs once after each subscription and once after expiry unless the first read already reached the expiry slot, then again on later roots while the node lags the expiry slot or reports a status that isn't finalized. |
| AI-enhanced transaction simulation | Reuse simulation results, logs, and errors for human-readable explanations in a separate framework after RPC; see [simulation explanations](transaction-simulation.md). |

- Confidential transfers remain conditional; agree on feasibility and the concrete flow before adding support.
- Account and rent reads serve token-transfer prerequisites and the agreed SOL-only account-discovery flow; general account exploration and node-version queries remain outside the current scope. Token ownership and address-history methods have no current agreed consumer and are not exposed.
- RPC completion means the agreed flows have the communication they need. Human-readable simulation explanations remain a separate milestone; AI exploration is parked. UI remains last.
- Public Solana mainnet (`https://api.mainnet.solana.com`), Helius, and QuickNode are the built-in providers; people can add custom HTTPS RPC URLs. Submission chooses ordinary RPC broadcast or one Helius Sender tier, never both; see [submission policy](transaction-workflow.md#submission-and-observation).
- The app reads, simulates, and subscribes at `finalized`, because Alpenglow makes `confirmed` and `finalized` equivalent ([Alpenglow](https://solana.com/upgrades/alpenglow), [commitments](https://docs.anza.xyz/consensus/commitments)).
- Preserve sanitized server errors with null response IDs. Successful results and attributed errors require matching IDs; missing or malformed ID fields are rejected.

## Rate limits

- Keep ordinary RPC and DAS requests single-attempt, without throttling or cooldowns. Expose HTTP `429` through `RPCError.http(statusCode:retryAfter:)`, preserving the sanitized `Retry-After` header. Subscriptions surface sanitized errors and do not reconnect themselves; Portfolio and the Confirmer reconnect only after errors that `RPCError.isRecoverable` accepts, never after a rate limit or a rejected key.
- Price providers follow the same error policy. Jupiter deduplicates addresses and paces batches of at most fifty at twenty requests/minute without a key or forty with a key. A failed batch throws without retrying or returning partial results. Reuse the provider to share its request budget; refresh scheduling belongs to the consumer.
- Consumers decide presentation and recovery. Portfolio keeps its cached snapshot and exposes the refresh error; the app may silently ignore the warning.
- Preserve each provider's submission error. Multi-submit attempts each enabled route once; one provider's rate limit must not cancel the others. Do not automatically resubmit.

## Provider limitations

Helius priority-fee estimation is verified only for account-based mainnet requests. Devnet and transaction-based V1 estimates are not verified as supported capabilities; do not add an automatic fallback. See [Helius's API contract](https://www.helius.dev/docs/api-reference/priority-fee/getpriorityfeeestimate).
