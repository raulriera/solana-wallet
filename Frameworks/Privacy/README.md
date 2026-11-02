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

`keys` comes from Wallet's `privateBalanceKeys`. `NoteSyncState.synced` reads one batch from the state's position, so a saved state syncs a long backlog over several calls; `syncedToEnd` reads until the indexer has no more. A sync counts a received note only after its Merkle proof leads to a root that its tree's account holds on chain, read through `rpc`. Notes whose root isn't on chain yet wait for the next sync, and notes whose proof fails are dropped. `ShieldedAccount.register(paidBy:)` and `ShieldedPool.deposit` make instructions, and `NoteSyncState.spend` makes a proved private transfer, reading queued nullifiers through `rpc` and proving through `prover`.
