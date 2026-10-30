# Transactions

Solana instructions, V1 message compilation, transaction decoding, and signature assembly. It does no networking and holds no private keys.

## Usage

```swift
import Transactions

let compiler: any MessageBuilding = MessageBuilder()
let assembler: any TransactionBuilding = TransactionBuilder()
let transfer = try SystemProgram.transfer(from: sender, to: recipient, lamports: 1_000_000)
let message = try compiler.message(
    instructions: [transfer],
    payer: sender,
    recentBlockhash: blockhash,
    configuration: configuration
)
let unsigned = try assembler.simulationTransaction(for: message)
```

`SystemProgram`, `MemoProgram`, and `TokenTransfer` make `Instruction` values that compose into one message. `TokenTransfer` supports SPL Token and Token-2022.
