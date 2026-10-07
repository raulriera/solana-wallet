# Portfolio

- Each account shows a manual token list: native SOL, USDC, and USDT by default, plus up to 50 tokens the person adds. People who need more tokens use another account.
- Search for tokens to add lists only tokens Jupiter verifies; pasting a mint address can add any token.
- Include native SOL and fungible SPL Token and Token-2022 tokens only. Non-fungible tokens (NFTs) will be included in a separate future milestone.
- Read balances with standard RPC, so every provider supports the portfolio. DAS does not supply balances or discover tokens.
- Keep balances exact and native SOL distinct from Wrapped SOL.
- Show logos only over HTTPS from the selected provider's CDN; today only Helius has one, through DAS lookups of the listed mints. SOL, USDC, and USDT use bundled logos; other tokens show their first letter.
- Fetch market prices through RPC's interchangeable `PriceProviding` contract. Jupiter is one implementation; its private response is transformed into `Quote`, keyed by mint, with a decimal unit price, currency, retrieval time, and optional 24-hour change. Missing quotes mean unknown value, and a missing change means an unknown change; neither is zero.
- Price providers identify their network. Jupiter supplies mainnet USD quotes; do not apply them to devnet balances. Currency conversion remains deferred.
- Deduplicate price mints and batch within the provider's limits. Jupiter sends at most fifty mints per request, spaced at twenty requests/minute without a key or forty with a key. HTTP `429` errors surface without retrying.
- Watch the wallet and its listed token accounts for confirmed changes, then read their balances again. Opening the portfolio and pull-to-refresh reload balances and prices; the app does not poll.
- When adding currency support, revisit `Amount` so asset and balance displays follow the device's locale and currency settings.
