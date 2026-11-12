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
let zolana = Zolana(network: .mainnet)
let registration = try await account.registration(using: rpc)
let notes = try await NoteSyncState().syncedToEnd(for: account, rpc: rpc, indexer: zolana)
let spend = try await notes.spend(lamports, to: .transfer(recipient), from: account, rpc: rpc, prover: zolana)
```

`keys` comes from Wallet's `privateBalanceKeys`. `syncedToEnd` reads the account's new notes and spends from the indexer; `synced` reads one batch, so a saved state catches up over several calls. Balances hold SOL and the `PrivateToken` assets.
