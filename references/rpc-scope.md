# RPC scope

- Add an RPC method only for an agreed wallet feature; a test or a possible future use doesn't justify one. General account exploration, token ownership, address history, and node-version queries are out of scope. Agree on confidential transfers before adding them.
- Connect directly to providers; no app-owned backend or proxy. Provider endpoints, authentication, batching, and response transforms stay inside RPC; consumers depend on provider-neutral protocols and values.
- Built-in providers: public Solana RPC (no key) and Helius (one key for mainnet and devnet); QuickNode is planned. Custom HTTPS RPC URLs serve mainnet only; with one selected, devnet requests fail with a typed error and never use another provider. Before saving a custom RPC, the app checks `GetMultipleAccounts`, `accountSubscribe`, `signatureSubscribe`, and `rootSubscribe` at its URL.
- Every wallet feature works on every provider. Only optional capabilities differ: Helius adds CDN logos and Solana Rings indexing and proofs.
- Read, simulate, and subscribe at `finalized`; Alpenglow makes `confirmed` and `finalized` equivalent ([Alpenglow](https://solana.com/upgrades/alpenglow)).
- Results and attributed errors require matching response IDs; keep sanitized server errors that have null IDs.

## Rate limits

- Send RPC and DAS requests once, without throttling or cooldowns. HTTP `429` surfaces as `RPCError.http(statusCode:retryAfter:)`. Subscriptions don't reconnect themselves; consumers reconnect only after errors that `RPCError.isRecoverable` accepts.
- Price providers pace batches within their request budget. Jupiter sends at most fifty mints per request, at twenty requests a minute without a key or forty with one. A failed batch throws without partial results. Reuse a provider to share its budget.
- Multi-route submission tries each route once; one route's rate limit doesn't cancel the others. Never resubmit automatically.
