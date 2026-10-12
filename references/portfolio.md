# Portfolio

- Each account shows a manual token list: native SOL, USDC, and USDT by default, plus up to 50 tokens the person adds. People who need more tokens use another account.
- People add a token by pasting its mint address. The app checks the address on chain and shows the token's on-chain name and symbol, and its logo where the provider has one, before adding it. Addresses that aren't fungible token mints, including NFTs, are refused.
- People can remove any listed token, including USDC and USDT; native SOL always stays. Removed defaults don't count toward the 50-token limit, even when added back.
- Include native SOL and fungible SPL Token and Token-2022 tokens only. Non-fungible tokens (NFTs) will be included in a separate future milestone.
- Read balances with standard RPC, so every provider supports the portfolio. DAS does not supply balances or discover tokens.
- Keep balances exact and native SOL distinct from Wrapped SOL.
- Show logos only over HTTPS from the selected provider's CDN; today only Helius has one, through DAS lookups of the listed mints. SOL, USDC, and USDT use bundled logos; other tokens show their first letter. A failed lookup leaves the letter until the next balance read. Switching providers removes saved logos; the new provider's logos arrive with the next balance read.
- Fetch market prices through RPC's interchangeable `PriceProviding` contract. Jupiter is one implementation; its private response is transformed into `Quote`, keyed by mint, with a decimal unit price, currency, retrieval time, and optional 24-hour change. Missing quotes mean unknown value, and a missing change means an unknown change; neither is zero.
- Price providers identify their network. Jupiter supplies mainnet USD quotes; do not apply them to devnet balances. Currency conversion remains deferred.
- Deduplicate price mints and batch within the provider's limits. Jupiter sends at most fifty mints per request, spaced at twenty requests/minute without a key or forty with a key. HTTP `429` errors surface without retrying.
- Watch the wallet and its listed token accounts for confirmed changes, then read their balances again. Opening the portfolio and pull-to-refresh reload balances and prices; the app does not poll.
- A dropped connection shows that balances may be out of date, then reconnects by itself. It waits 2 seconds, doubling after each failed attempt up to a minute, and reads balances again after it reconnects. Rate limits, rejected keys, and other refusals wait for pull-to-refresh, a token-list change, or the portfolio opening again; each of these also reconnects at once.
- Observation refreshes require a response at or after the newest confirmed change slot. An older response leaves the cached snapshot intact and surfaces a failure without automatic retries.
- When adding currency support, revisit `Amount` so asset and balance displays follow the device's locale and currency settings.
