# Portfolio

Native SOL and fungible-token portfolios with persistent caching, independent price refreshes, and reconciliation after confirmed account changes. Holdings and metadata come from the selected RPC provider's DAS interface.

## Swift API

Inject [`PortfolioProviding`](Service/PortfolioProviding.swift), implemented by `Portfolio`. Given a Helius API key, a wallet address, and a caller-owned `receive` handler:

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

## State and lifetime

[`Update`](Service/Update.swift) carries a complete optional snapshot and refresh phase. A missing snapshot differs from an empty wallet. Retrieval failures retain the last complete snapshot; persistence failures expose the newly fetched snapshot with an error.

Consumers combining streams use `revision` to order status and `snapshotRevision` to order holdings independently. Revisions are comparable only within one provider instance, and replayed snapshots keep their original revision.

Reuse a service across windows to share in-flight refreshes and one subscription connection per observed wallet. Each consumer gets its own stream. The caller owns task lifetimes; cancel consumption when observation is no longer needed.

Cache entries are separated by wallet and network. Confirmed-change bursts are coalesced, with bounded follow-up reads while DAS indexing catches up. Request failures and disconnections surface without automatic retries or reconnection; there is no periodic polling.

## Holdings

Balances use exact integer units and decimal precision. `Amount.formatted(locale:)` preserves precision and follows the supplied locale, defaulting to the device locale. Missing prices remain unavailable rather than zero; native SOL and wrapped SOL remain separate holdings.

NFTs, currency conversion, and portfolio loading without DAS are unsupported. Metadata contains media references; the framework does not download images or off-chain metadata documents. See [portfolio behavior](../references/portfolio.md).
