# Transaction workflow

`TransactionCoordinator: TransactionCoordinating` is the internal app entry point. Configure it once with the read RPC, protected recovery store, submission providers, and strategy. `Account` identifies retained recovery and its derived address without holding keys.

```swift
let transactions = try TransactionCoordinator(
    rpc: rpc, store: recoveryStore,
    rpcs: [rpc, Solana(network: rpc.network)], strategy: .none
)
let wallet = Account(id: accountID, recoveryID: recoveryID, address: address, path: .solana)
let simulation = try await transactions.simulate([
    SystemProgram.transfer(from: wallet.address, to: recipient, lamports: 1_000_000),
    MemoProgram.memo("Payment reference"),
    customInstruction
], using: wallet)
// Present the review and obtain explicit approval.
let submission = try await transactions.submit(simulation)
// submission.signature is available at once; then watch the outcome.
let result = try await transactions.confirm(submission)
// result.outcome is succeeded, failed (the fee is still paid), or dropped.
```

- Any instruction collection uses this path. Supply `using: [payer, otherSigner]` when several local wallets must sign; the first pays fees. A redeem code's one-time account signs as an `Authority.oneTime` in memory, without recovery or authentication; it still goes through the same simulation, approval, and lifetime checks. Program helpers produce instructions; views don't assemble wire bytes, blockhashes, signature slots, or submission requests.
- `transfer(amount, token: mint, using: wallet, to: recipient)` is a convenience over the same pipeline. Omit `token` for SOL. Token resolution reads the mint, the recipient, and both token programs' associated accounts in one finalized request, then reads the Token-2022 epoch and a new destination's rent together, and builds account creation/memo/checked-transfer instructions. Optional `source` selects a non-associated account. Rent is queried before simulation and reported separately; RPC failures propagate.
- `simulate(importedTransaction, using: wallet)` preserves the original message and cosignatures. The import boundary decodes binary/Base64 through `TransactionDecoding`. After approval, `sign(simulation)` returns a typed, possibly partially signed transaction without broadcasting. `submit(simulation)` requires every outstanding signer to be available locally before authentication.
- With no explicit coordinator `configuration`, preparation simulates a provisional message with maximum allowed resources, then adds a 10% usage margin within protocol limits. Missing usage in a successful estimate throws. A failed estimate retains its diagnostics for review. Fee estimation and the final simulation evaluate the exact final message, concurrently, at or after the prerequisite context. Explicit configuration bypasses estimation and is never silently changed.
- `Simulation` exposes the transaction, network, optional network fee and block-height expiry, final diagnostics, and service tips. The token convenience also exposes its validated token debit and estimated destination deposit. Existing token destinations report zero deposit; other compositions report `nil`. `balanceChanges` reports the node's SOL and raw token differences per owner and asset from its balances before and after execution, or `nil` when unavailable or unattributable; token account deposits count as the token account's SOL, not the owner's. Changes are observations and do not interpret arbitrary programs.
- Each review permits one signing attempt, shared across copies and concurrent calls. Reusing it is rejected; another attempt requires a new simulation and approval.
- The coordinator privately binds each review to its selected local wallets and submission policy. Approval is distinct from device authentication. Submission revalidates the message, signatures, network, fee, and original lifetime before wallet access. Signing happens immediately after authentication so recovery is released first; the lifetime is then checked again and an expired signature is discarded. Sending checks the message and signatures again locally, without another network read. Changed or expired messages require another simulation and approval. Recovery stays local to signing.
- Generic local instructions are recompiled only to verify equality with the reviewed bytes. Imported messages are never rebuilt. Signing uses the same signature-slot validation for both. Simulation success doesn't establish intent or scam safety; human-readable interpretation remains deferred.

## Submission and observation

- `none` submits identical signed bytes once, concurrently, through configured same-network ordinary RPCs. `standard` and `premium` select Sender exclusively; no simultaneous ordinary broadcast or fallback. DAS serves portfolio only.
- Sender tips are ordinary instructions added before resource estimation and review, ahead of the caller's instructions so a payment can stay last. Standard uses a 5,000-lamport tip and positive priority fee; premium uses a 1,000,000-lamport tip and at least 5,000 priority-fee lamports. Automatic configuration uses the selected minimum; an insufficient explicit fee throws. These are minimum bids, not landing guarantees.
- Sender is mainnet-only, with a stable tip recipient per client and no API key or warming timer. Imported transactions retain their existing payments; Sender can reject missing requirements without fallback. Changing strategy requires a new coordinator and review.
- Internal `Submitter` validates all signatures, retains existing cosignatures, and uses finalized preflight with zero node retries. Each route runs in a structured task group. Acceptance by any route yields a receipt; aggregate failure retains the signature, network, and independent errors. Dispatch failure or cancellation can leave delivery unknown.
- `submit(simulation)` returns the receipt once sending settles and a route accepted it, without waiting for its outcome. `DeliveryError` retains that receipt and the original cause if delivery or the watch throws after signing, including a rate limit, a rejected key, and cancellation. The app can pass that receipt to `confirm(submission)` without signing again.
- `confirm(submission)` watches a receipt in real time through internal `Confirmer`, without reading recovery or sending. One connection carries `signatureSubscribe` at finalized and `rootSubscribe`. After each subscription, one status read catches up on an earlier landing, alongside a finalized block-height read until the blockhash expires; roots schedule later block-height reads. The result is succeeded or failed from a finalized landing or status, keeping execution errors, or dropped when no status exists after a finalized block height passes the receipt's last valid one. There is no timeout or unknown result.
- The watch reconnects after errors that `RPCError.isRecoverable` accepts and after 30 seconds without a root, waiting 2 seconds, doubling up to a minute, and resetting after a subscription and its first reads succeed. Rate limits, rejected keys, refused subscriptions, and malformed responses throw. Nothing rebuilds, resigns, or resubmits; a receipt can be watched again.
- Rate-limit errors propagate to the app. Frameworks don't add queues, automatic retries, or fallback providers.

Sources: [Kit's shared lifecycle](https://www.solanakit.com/docs/guides/sending-transactions), [Sender standard](https://www.helius.dev/docs/sending-transactions/sender-swqos-only.md), [Sender premium](https://www.helius.dev/docs/sending-transactions/sender-max.md), [submission semantics](https://solana.com/docs/rpc/http/sendtransaction.md), [blockhash validity](https://solana.com/docs/rpc/http/isblockhashvalid.md), [signature status](https://solana.com/docs/rpc/http/getsignaturestatuses.md), [signature subscription](https://solana.com/docs/rpc/websocket/signaturesubscribe.md), [root subscription](https://solana.com/docs/rpc/websocket/rootsubscribe.md).
