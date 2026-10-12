# Transaction workflow

`TransactionCoordinator: TransactionCoordinating` is the internal app entry point. Configure it once with the read RPC, protected recovery store, submission providers, and strategy. `Account` identifies retained recovery and its derived address without holding keys.

```swift
let transactions = try TransactionCoordinator(
    rpc: rpc, store: recoveryStore,
    rpcs: [rpc, Solana(network: rpc.network)], strategy: .none
)
let wallet = Account(id: accountID, recoveryID: recoveryID, address: address, index: accountIndex)
let simulation = try await transactions.simulate([
    SystemProgram.transfer(from: wallet.address, to: recipient, lamports: 1_000_000),
    MemoProgram.memo("Payment reference"),
    customInstruction
], using: wallet)
// Present the review and obtain explicit approval.
let result = try await transactions.confirm(simulation)
// Inspect result.outcome: confirmed execution can still fail.
```

- Any instruction collection uses this path. Supply `using: [payer, otherSigner]` when several local wallets must sign; the first pays fees. Program helpers produce instructions; views don't assemble wire bytes, blockhashes, signature slots, or submission requests.
- `transfer(amount, token: mint, using: wallet, to: recipient)` is a convenience over the same pipeline. Omit `token` for SOL. Token resolution discovers the mint and accounts, rereads them at one confirmed context, checks the Token-2022 epoch, and builds account creation/memo/checked-transfer instructions. Optional `source` selects a non-associated account. Rent is queried before simulation and reported separately; RPC failures propagate.
- `simulate(importedTransaction, using: wallet)` preserves the original message and cosignatures. The import boundary decodes binary/Base64 through `TransactionDecoding`. After approval, `sign(simulation)` returns a typed, possibly partially signed transaction without broadcasting. `confirm(simulation)` requires every outstanding signer to be available locally before authentication.
- With no explicit coordinator `configuration`, preparation simulates a provisional message with maximum allowed resources, then adds a 10% usage margin within protocol limits. Missing usage in a successful estimate throws. A failed estimate retains its diagnostics for review. Fee estimation and the final simulation evaluate the exact final message, concurrently, at or after the prerequisite context. Explicit configuration bypasses estimation and is never silently changed.
- `Simulation` exposes the transaction, network, optional network fee and block-height expiry, final diagnostics, and service tips. The token convenience also exposes its validated token debit and estimated destination deposit. Existing token destinations report zero deposit; other compositions report `nil`. `balanceChanges` reports the node's SOL and raw token differences per owner and asset from its balances before and after execution, or `nil` when unavailable or unattributable; token account deposits count as the token account's SOL, not the owner's. Changes are observations and do not interpret arbitrary programs.
- Each review permits one signing attempt, shared across copies and concurrent calls. Reusing it is rejected; another attempt requires a new simulation and approval.
- The coordinator privately binds each review to its selected local wallets and submission policy. Approval is distinct from device authentication. Confirmation revalidates the message, signatures, network, fee, and original lifetime before wallet access and submission. Signing happens immediately after authentication so recovery is released first; the lifetime is then checked again and an expired signature is discarded. Changed or expired messages require another simulation and approval. Recovery stays local to signing.
- Generic local instructions are recompiled only to verify equality with the reviewed bytes. Imported messages are never rebuilt. Signing uses the same signature-slot validation for both. Simulation success doesn't establish intent or scam safety; human-readable interpretation remains deferred.

## Submission and observation

- `none` submits identical signed bytes once, concurrently, through configured same-network ordinary RPCs. `standard` and `premium` select Sender exclusively; no simultaneous ordinary broadcast or fallback. DAS serves portfolio only.
- Sender tips are ordinary instructions added before resource estimation and review, ahead of the caller's instructions so a payment can stay last. Standard uses a 5,000-lamport tip and positive priority fee; premium uses a 1,000,000-lamport tip and at least 5,000 priority-fee lamports. Automatic configuration uses the selected minimum; an insufficient explicit fee throws. These are minimum bids, not landing guarantees.
- Sender is mainnet-only, with a stable tip recipient per client and no API key or warming timer. Imported transactions retain their existing payments; Sender can reject missing requirements without fallback. Changing strategy requires a new coordinator and review.
- Internal `Submitter` validates all signatures, retains existing cosignatures, and uses confirmed preflight with zero node retries. Each route runs in a structured task group. Acceptance by any route yields a receipt; aggregate failure retains the signature, network, and independent errors. Dispatch failure or cancellation can leave delivery unknown.
- `DeliveryError` retains the signed transaction receipt and original cause if delivery or observation throws, including cancellation. The app can reconcile that signature without signing again.
- Internal `Confirmer` observes that receipt with an injected `Clock`, one-second polling, and a 60-second deadline. Confirmed/finalized outcomes retain execution errors. Timeout, cancellation, or RPC errors never rebuild, resign, or resubmit; a receipt can be observed again independently.
- Rate-limit errors propagate to the app. Frameworks don't add queues, automatic retries, or fallback providers.

Sources: [Kit's shared lifecycle](https://www.solanakit.com/docs/guides/sending-transactions), [Sender standard](https://www.helius.dev/docs/sending-transactions/sender-swqos-only.md), [Sender premium](https://www.helius.dev/docs/sending-transactions/sender-max.md), [submission semantics](https://solana.com/docs/rpc/http/sendtransaction.md), [blockhash validity](https://solana.com/docs/rpc/http/isblockhashvalid.md), [signature status](https://solana.com/docs/rpc/http/getsignaturestatuses.md).
