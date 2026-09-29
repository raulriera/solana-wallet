# Portfolio

- Currently include native SOL and fungible tokens only; exclude NFTs and other asset kinds. Request fungibles at the DAS source and enforce the same scope before creating holdings. Older mixed-asset caches are incompatible and must refresh before providing holdings.
- Non-fungible tokens (NFTs) will be included in a separate future milestone.
- Required data: exact amounts, name, symbol, valuation, and rich metadata. Valuations must support independent live updates; refresh scheduling remains to be agreed.
- `Portfolio` implements `PortfolioProviding`; RPC owns the selected provider's DAS requests and response decoding. Portfolio depends on the provider-neutral RPC contract.
- DAS is exclusively for portfolio viewing. Use the selected provider's DAS capability for holdings and metadata; behavior without DAS remains deferred.
- Preserve descriptions, website and metadata URLs, media files with MIME/CDN information, typed attributes, collection metadata, creators, asset kinds, token standards, and metadata mutability. Keep provider decoding private and carry shared metadata values unchanged into persisted holdings.
- Preserve reported supply, token program, mint/freeze authorities, ownership/delegation, royalties, edition supply, burned status, and compression details as asset state for portfolio viewing. These values do not validate transactions.
- Keep native SOL and Wrapped SOL distinct. Preserve Wrapped SOL's supplied metadata; native SOL retains its own name, symbol, balance, and identity. Reuse the native mint's image from an owned Wrapped SOL holding, or use one same-network `GetAsset` lookup when needed. Preserve valid provider images; a bundled SOL image is only justified when no image source exists. Do not fetch off-chain JSON or media as part of a portfolio refresh.
- Fetch market prices through RPC's interchangeable `PriceProviding` contract. Jupiter is one implementation; its private response is transformed into `Quote`, keyed by mint, with a decimal unit price, currency, and retrieval time. Response decoding and conversion stay private to each provider; shared types use our domain names. Missing quotes mean unknown value, never zero.
- Price providers identify their network. Jupiter supplies mainnet USD quotes; do not apply them to devnet balances. Retrieval time is not the underlying market-update time. Currency conversion remains deferred.
- Independent pricing is available in RPC; Portfolio snapshot refresh still consumes DAS prices. Connecting independent quotes to valuations remains pending.
- Await `updates(for:)` to register a consumer, then read its stream for one cache-and-refresh cycle. Registration completes before the stream returns; network results arrive through the stream.
- Persist snapshots by wallet and network. Reuse existing data before refreshing; a missing snapshot is distinct from a successfully empty wallet.
- Replace stored holdings only after all pages and required metadata lookups succeed. Fetch failures and cancellation preserve the preceding snapshot and its retrieval time. Storage failures expose the fresh snapshot alongside the error.
- Share concurrent refreshes without sharing a consumer's stream. Removing wallet data cancels its refresh and prevents obsolete results from restoring the cache.
- Keep metadata and prices optional, balances exact, native SOL distinct, and incomplete valuations explicit.
- When adding currency support, revisit `Amount` so asset and balance displays follow the device's locale and currency settings.
