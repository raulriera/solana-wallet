# Portfolio

A wallet's SOL and listed token balances, with prices, local caching, and new reads after on-chain changes. It works with any RPC provider.

## Usage

```swift
import Portfolio
import RPC

let portfolio: any PortfolioProviding = Portfolio(
    rpc: SolanaRPC(network: .mainnet),
    tokenListDirectory: .applicationSupportDirectory.appending(path: "TokenLists", directoryHint: .isDirectory),
    cacheDirectory: .cachesDirectory.appending(path: "Portfolio", directoryHint: .isDirectory)
)
for await update in await portfolio.updates(for: owner) {
    receive(update)
}
```

Pass a `PriceProviding` client as `prices:` to value the holdings. `Portfolio` also implements `TokenListProviding`, which adds and removes the tokens each account shows.
