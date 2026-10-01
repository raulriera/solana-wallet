# Portfolio

Native SOL and fungible-token portfolios with persistent caching, independent price refreshes, and reconciliation after confirmed account changes. Holdings and metadata come from the selected RPC provider's DAS interface.

## Example Usage

Inject [`PortfolioProviding`](Sources/Service/PortfolioProviding.swift), implemented by `Portfolio`, with a DAS-capable RPC client. This example uses a built-in provider with a caller-supplied API key, wallet address, and `receive` handler:

```swift
import Portfolio
import RPC

let service: any PortfolioProviding = Portfolio(
    rpc: HeliusRPC(apiKey: apiKey, network: .mainnet)
)
for await update in await service.updates(for: owner, policy: .ifStale) {
    receive(update)
}
```

An optional same-network `PriceProviding` provider enables independent prices; without one, holdings retain available DAS valuations. An optional `AccountChangeProviding` provider supplies subscriptions, defaulting to the RPC client's capability.

| Operation | Behavior |
| --- | --- |
| `updates(for:policy:)` | Finite stream of cached state and any required refresh. `.ifStale` checks holdings and prices separately against five minutes; `.reload` requests fresh data. |
| `priceUpdates(for:policy:)` | Revalue cached holdings without querying DAS. Requires existing holdings and a price provider. |
| `observations(for:)` | Subscribe before the initial reload, then reconcile confirmed changes until cancellation or subscription failure. |
| `removeData(for:)` | Remove the wallet's local cache and stop its active work. |
