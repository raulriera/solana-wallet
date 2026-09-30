# Transactions

Composable Solana instructions, V1 message compilation, transaction decoding, and signature verification and assembly. Construction is synchronous, bounded, and independent of networking and private keys.

## Example Usage

| Contract | Implementation | Purpose |
| --- | --- | --- |
| [`MessageBuilding`](Message/MessageBuilding.swift) | `MessageBuilder` | Compile ordered instructions with an explicit payer, blockhash, and resource configuration. |
| [`TransactionDecoding`](Decoding/TransactionDecoding.swift) | `TransactionDecoder` | Decode binary or Base64 V1 envelopes while preserving exact message bytes and signature slots. |
| [`TransactionBuilding`](Signing/TransactionBuilding.swift) | `TransactionBuilder` | Create simulation envelopes, verify signatures, and insert a signature into its required empty slot. |

Given validated sender and recipient `Address` values, a recent blockhash, and a `Configuration` containing estimated fees and resource limits:

```swift
import Transactions

let compiler: any MessageBuilding = MessageBuilder()
let assembler: any TransactionBuilding = TransactionBuilder()
let transfer = try SystemProgram.transfer(
    from: sender,
    to: recipient,
    lamports: 1_000_000
)
let message = try compiler.message(
    instructions: [transfer],
    payer: sender,
    recentBlockhash: blockhash,
    configuration: configuration
)
let unsigned = try assembler.simulationTransaction(for: message)
```

`unsigned` contains empty signature slots for simulation with signature verification disabled. Signing and submission are separate operations.

## Composition and validation

- `Instruction` carries a program address, ordered account permissions, and opaque data. `SystemProgram.transfer`, `MemoProgram.memo`, and `TokenTransfer.instructions(payer:)` produce the same composable values.
- The compiler merges permissions, preserves instruction order and repeated arguments, and supports separate fee payers and authorities. Oversized compositions throw rather than splitting into multiple transactions.
- [`Configuration`](Message/Configuration.swift) specifies total priority-fee lamports, compute units, loaded-account bytes, and optional heap size. Limits are validated without clamping.
- Only V1 envelopes are supported, bounded to 4,096 bytes, 64 accounts, 64 instructions, and 12 signatures.
- Decoding establishes structure, not signature validity or instruction meaning. Signature insertion verifies occupied slots and the new signature, preserving every other byte.

`TokenMint`, `TokenAccount`, and `TokenTransfer` share validation for SPL Token and Token-2022. Transfers use integer base units, validate account relationships and supported extensions, and can include destination-account creation and memos. Unsupported extensions fail explicitly. See [token behavior and limits](../references/transactions.md).

The caller supplies current account observations, blockhash validity, fee estimates, simulation, user approval, signing, and submission. Address validation alone does not establish account existence or ownership.
