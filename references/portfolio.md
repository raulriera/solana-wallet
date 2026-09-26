# Portfolio

- `Portfolio` implements `PortfolioProviding`; RPC owns DAS requests and response decoding.
- Await `updates(for:)` to register a consumer, then read its stream for one cache-and-refresh cycle. Registration completes before the stream returns; network results arrive through the stream.
- Persist snapshots by wallet and network. Reuse existing data before refreshing; a missing snapshot is distinct from a successfully empty wallet.
- Replace stored holdings only after all pages succeed. Fetch failures and cancellation preserve the preceding snapshot and its retrieval time. Storage failures expose the fresh snapshot alongside the error.
- Share concurrent refreshes without sharing a consumer's stream. Removing wallet data cancels its refresh and prevents obsolete results from restoring the cache.
- Keep metadata and prices optional, balances exact, native SOL distinct, and incomplete valuations explicit.
- When adding currency support, revisit `Amount` so asset and balance displays follow the device's locale and currency settings.
