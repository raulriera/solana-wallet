# Portfolio

- Required data: exact amounts, name, symbol, valuation, and rich metadata. Valuations must support independent live updates; refresh scheduling remains to be agreed.
- `Portfolio` implements `PortfolioProviding`; RPC owns the selected provider's DAS requests and response decoding. Portfolio depends on the provider-neutral RPC contract.
- DAS is exclusively for portfolio viewing. Use the selected provider's DAS capability for holdings and metadata; behavior without DAS remains deferred.
- Fetch market prices through RPC's interchangeable `PriceProviding` contract. Jupiter is one implementation; its private response is transformed into `Quote`, keyed by mint, with a decimal unit price, currency, retrieval time, and optional source block reference. Missing quotes mean unknown value, never zero.
- Price providers identify their network. Jupiter supplies mainnet USD quotes; do not apply them to devnet balances. Retrieval time is not the underlying market-update time. Currency conversion remains deferred.
- Independent pricing is available in RPC; Portfolio snapshot refresh still consumes DAS prices. Connecting independent quotes to valuations and adding rich metadata remain pending.
- Await `updates(for:)` to register a consumer, then read its stream for one cache-and-refresh cycle. Registration completes before the stream returns; network results arrive through the stream.
- Persist snapshots by wallet and network. Reuse existing data before refreshing; a missing snapshot is distinct from a successfully empty wallet.
- Replace stored holdings only after all pages succeed. Fetch failures and cancellation preserve the preceding snapshot and its retrieval time. Storage failures expose the fresh snapshot alongside the error.
- Share concurrent refreshes without sharing a consumer's stream. Removing wallet data cancels its refresh and prevents obsolete results from restoring the cache.
- Keep metadata and prices optional, balances exact, native SOL distinct, and incomplete valuations explicit.
- When adding currency support, revisit `Amount` so asset and balance displays follow the device's locale and currency settings.
