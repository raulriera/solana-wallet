# RPC scope

- Add an RPC method only for an agreed wallet feature; a test or a possible future use doesn't justify one. General account exploration, token ownership, address history, and node-version queries are out of scope. Agree on confidential transfers before adding them.
- Custom HTTPS RPC URLs serve mainnet only; with one selected, devnet requests fail with a typed error and never use another provider. Check a custom RPC URL before saving it.
- Read, simulate, and subscribe at `finalized`.
- Subscriptions don't reconnect themselves; consumers reconnect only after errors that `RPCError.isRecoverable` accepts.
- A failed price batch throws without partial results. Reuse a price provider so its batches share one budget.
