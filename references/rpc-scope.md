# RPC scope

- Add an RPC method only for an agreed wallet feature; a test or a possible future use doesn't justify one. General account exploration, token ownership, address history, and node-version queries are out of scope. Agree on confidential transfers before adding them.
- Connect directly to providers; no app-owned backend or proxy. Provider endpoints, authentication, batching, and response transforms stay inside the RPC framework; consumers depend on provider-neutral protocols and values.
- Built-in RPC providers: public Solana RPC (no key) and Helius (one key for mainnet and devnet). Custom HTTPS RPC URLs serve mainnet only; with one selected, devnet requests fail with a typed error and never use another provider. Before saving a custom RPC, the app checks `GetMultipleAccounts`, `accountSubscribe`, `signatureSubscribe`, and `rootSubscribe` at its URL.
- Every standard wallet feature works on every RPC provider. Optional capabilities are protocols, and a provider has a capability when it conforms: `LogoProviding` for CDN logos, `RingsProviding` for Solana Rings private balances.
- Read, simulate, and subscribe at `finalized`; Alpenglow makes `confirmed` and `finalized` equivalent ([Alpenglow](https://solana.com/upgrades/alpenglow)).
- Results and attributed errors require matching response IDs; keep sanitized server errors that have null IDs.

## Rate limits

- Send RPC and DAS requests once, without throttling or cooldowns. HTTP `429` surfaces as `RPCError.http(statusCode:retryAfter:)`. Subscriptions don't reconnect themselves; consumers reconnect only after errors that `RPCError.isRecoverable` accepts.
- Price providers pace batches within their request budget. Jupiter and custom price servers get fifty mints per request, three seconds apart, which fits Jupiter's keyless limit. A failed batch throws without partial results. Reuse a provider to share its budget.
- Prices come from Jupiter or a custom HTTPS price server that answers in `Quote`'s shape.
