# Privacy

Solana Rings private balances: an account's registration, its received notes, deposits, and private transfers and withdrawals with their proofs. Instructions are [Transactions](../Transactions/README.md) values, and reads go through [RPC](../RPC/README.md).

## Notes

A private balance is a set of notes. A note is an unspent output (UTXO) of the pool: an amount of one asset that one account owns. The pool keeps each note's commitment in a tree and, after the note is spent, its nullifier. One transaction spends at most 40 notes from at most 2 trees.

A deposit makes one note and needs no proof.

```mermaid
flowchart TD
    start(["Deposit an amount"]) --> sync["Sync the account's notes"]
    sync --> many{"More than 40 notes<br/>of the asset?"}
    many -- No --> deposit["Build the deposit instruction"]
    many -- Yes --> merge[["Prove a merge"]]
    merge --> deposit
    deposit --> send[/"Send one transaction:<br/>the merge, if any, then the deposit"/]
    send --> done(["One new note of the amount"])
```

A transfer or a withdrawal spends notes and needs a proof. Notes that one transaction can't spend are merged first.

```mermaid
flowchart TD
    start(["Transfer or withdraw an amount"]) --> sync["Sync the account's notes"]
    sync --> covers{"Do the notes<br/>cover the amount?"}
    covers -- No --> insufficient(["Insufficient funds"])
    covers -- Yes --> fits{"Do at most 40 notes<br/>from at most 2 trees<br/>cover it?"}
    fits -- No --> merge[["Prove a merge"]]
    merge --> sendMerge[/"Send one transaction:<br/>the merge"/]
    sendMerge --> sync
    fits -- Yes --> spend["Select the notes and<br/>prove the spend"]
    spend --> send[/"Send one transaction:<br/>the spend"/]
    send --> done(["The recipient's note or the public amount,<br/>and one note of change"])
```

A merge is a transfer of the notes that one transaction spends to the account itself, which leaves one note with their total.

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

`keys` comes from Wallet's `privateBalanceKeys`.
