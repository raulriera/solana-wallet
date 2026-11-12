# Portfolio

- Each account has a manual token list: native SOL, USDC, and USDT by default (SOL only on devnet), plus tokens the person adds, up to 50 tokens in all, counting native SOL, so one price request covers the list. Native SOL can't be removed.
- People add a token by pasting its mint address. Only fungible SPL Token and Token-2022 mints are accepted; NFTs are deferred.
- Read balances with standard RPC, so every provider supports the portfolio. DAS only looks up logos on the selected provider's CDN, over HTTPS. Never request creator-hosted or off-chain artwork.
- Keep balances exact, and native SOL distinct from Wrapped SOL. A missing quote is an unknown value and a missing change is an unknown change, never zero. Devnet shows amounts without value.
- When another address controls a token's associated account, show no balance, value, or price for it.
- Watch the wallet and its token accounts for finalized changes, then read balances again. The app doesn't poll.
- Dropped connections and server failures (`RPCError.isRecoverable`) reconnect by themselves. Rate limits and rejected keys wait for the person: pull-to-refresh, a token-list change, or reopening the portfolio. Keep data on screen while either happens.
