# Transactions

Builds Solana instructions, compiles them into V1 messages, decodes transactions, and assembles signatures. Token instructions support SPL Token and Token-2022. It does no networking and holds no private keys.

## Transaction workflow

One send goes from instructions to one of three outcomes. This framework compiles the message and assembles the signatures; the app does the other steps.

```mermaid
flowchart TD
    start(["Instructions"]) --> simulate["Compile a V1 message<br/>and simulate it"]
    simulate --> approve["The person approves<br/>the review"]
    approve --> sign["Authenticate and sign"]
    sign --> send[/"Send it and watch<br/>until it's finalized or<br/>its blockhash expires"/]
    send --> resend{"Dropped in a send<br/>of several, and sent<br/>again fewer than<br/>2 times?"}
    resend -- Yes --> background{"Did the app go<br/>to the background?"}
    resend -- No --> follows{"Does another<br/>transaction follow?"}
    follows -- Yes --> landed{"Did it succeed?"}
    landed -- No --> stopped(["The send ends unfinished"])
    landed -- Yes --> background
    follows -- No --> outcome{"What is<br/>the outcome?"}
    outcome -- Succeeded --> succeeded(["Succeeded"])
    outcome -- Failed --> failed(["Failed"])
    outcome -- Dropped --> dropped(["Dropped"])
    background -- Yes --> stopped
    background -- No --> next["Simulate the next<br/>transaction, or the<br/>dropped one again"]
    next -- "Same authentication" --> sign
```

## Usage

```swift
import Transactions

let compiler = MessageBuilder()
let assembler = TransactionBuilder()
let transfer = try SystemProgram.transfer(from: sender, to: recipient, lamports: 1_000_000)
let message = try compiler.message(
    instructions: [transfer],
    payer: sender,
    recentBlockhash: blockhash,
    configuration: configuration
)
let unsigned = try assembler.simulationTransaction(for: message)
```
