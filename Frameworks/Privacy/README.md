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
let registration = try await account.registration(using: rpc)
let notes = try await NoteSyncState().synced(for: account, using: helius)
```

`keys` comes from Wallet's `privateBalanceKeys`. `ShieldedAccount.register(paidBy:)` and `ShieldedPool.deposit` make instructions, and `NoteSyncState.spend` makes a proved private transfer.
