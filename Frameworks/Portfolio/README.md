# Portfolio

Native SOL and each account's listed tokens, with persistent caching, independent price refreshes, and new balance reads after confirmed changes. One standard `getMultipleAccounts` request reads the wallet and every listed token's associated token account, so any RPC provider works.

## Example Usage

Inject [`PortfolioProviding`](Sources/Service/PortfolioProviding.swift), implemented by `Portfolio`, with any RPC client. This example uses Solana's public endpoint, a caller-supplied wallet address, and a `receive` handler:

```swift
import Portfolio
import RPC

let service: any PortfolioProviding = Portfolio(rpc: Solana(network: .mainnet))
for await update in await service.updates(for: owner, policy: .ifStale) {
    receive(update)
}
```

An optional same-network `PriceProviding` provider enables prices, including each quote's 24-hour change when the provider supplies one; without one, holdings stay unpriced. An optional `AccountChangeProviding` provider supplies subscriptions, defaulting to the RPC client's capability. An RPC client that implements `LogoProviding`, such as `HeliusRPC`, adds logos to the listed tokens after each balance read; a failed lookup leaves them out until the next read.

| Operation | Behavior |
| --- | --- |
| `updates(for:policy:)` | Finite stream of cached state and any required refresh. `.ifStale` checks holdings and prices separately against five minutes; `.reload` requests fresh data and connects a disconnected observation again. |
| `priceUpdates(for:policy:)` | Revalue cached holdings without reading balances again. Requires existing holdings and a price provider. |
| `observations(for:)` | Watch the wallet and each listed token account before the initial reload, then read balances again after confirmed changes until cancellation. A dropped connection reports its error and reconnects after 2 seconds, doubling the wait after each failed attempt up to a minute; rate limits and other refusals wait for a reload, a token-list change, or a new consumer. |
| `removeData(for:)` | Remove the wallet's local cache and token list, and stop its active work. |
| `providerDidChange()` | After the RPC client switches providers, end every observation and refresh and remove logos from saved snapshots; observe again to use the new provider. |

## Token Lists

Each account keeps a list of the tokens it shows besides native SOL. `Portfolio` also implements [`TokenListProviding`](Sources/TokenList/TokenListProviding.swift): new mainnet lists hold USDC and USDT, whose mint addresses `DefaultToken` names, devnet lists start empty, and people can add up to 50 tokens. Lists are saved per account and network in Application Support. A saved list that can't be read throws `TokenListError.unreadable` instead of returning the defaults. After a change, an observed account watches its new list and reads balances once; otherwise the next reload reads the new list. Share one `Portfolio` per network so that edits from several windows stay serialized.

| Operation | Behavior |
| --- | --- |
| `tokenList(for:)` | The account's saved list, or the network's defaults when it has none. |
| `addToken(_:for:)` | Append and save a token; a listed token keeps its place, and the 51st added token throws `TokenListError.limitReached`. |
| `removeToken(_:for:)` | Remove and save a token; cached holdings drop it at once. |
| `token(at:)` | Look up a pasted mint address for a preview: one standard request reads the mint and its Metaplex metadata account, and a provider that hosts logos adds the logo. Other accounts throw `TokenLookupError.notToken`, and NFTs `.nonFungible`. |
