# Privacy

Solana Rings private balances: an account's registration, its received notes, deposits, and private transfers and withdrawals with their proofs. Instructions are [Transactions](../Transactions/README.md) values, and reads go through [RPC](../RPC/README.md).

## Usage

```swift
import Privacy
import RPC
import Transactions

let account = try ShieldedAccount(
    signingAddress: Address(address),
    nullifierSecret: keys.nullifierSecret,
    viewingKey: keys.viewingKey
)
let rpc = HeliusRPC(apiKey: apiKey, network: .mainnet)
let registration = try await account.registration(using: rpc)
let notes = try await NoteSyncState().syncedToEnd(for: account, rpc: rpc, indexer: rpc)
let spend = try await notes.spend(amount, of: .token(.usdc), to: .transfer(recipient), from: account, rpc: rpc, prover: rpc)
```

`keys` comes from Wallet's `privateBalanceKeys`. Balances hold SOL and the `PrivateToken` assets.
