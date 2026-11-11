# Transactions

Builds Solana instructions, compiles them into V1 messages, decodes transactions, and assembles signatures. Token instructions support SPL Token and Token-2022. It does no networking and holds no private keys.

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
