# Transaction workflow

Internal app coordination follows [architecture](architecture.md). Services live under `widgets/Transactions`; app-hosted `widgetsTests` covers their behavior.

## Approved next submission behavior

These decisions extend the current single-provider implementation described below.

- Include public Solana mainnet as a built-in provider. Submission eligibility depends only on activation, network, and support for the chosen route. One eligible provider receives one submission; multiple eligible providers receive concurrent submissions.
- Submit the exact same signed transaction to every enabled provider on its network. Keep one signature and confirmation outcome; never rebuild or resign per provider.
- Attempt each route once. Retain independent errors so one failed provider does not cancel another submission. An acknowledgment establishes acceptance, not execution; dispatch failures can leave delivery unknown.
- Offer Helius Sender as an optional additional submission route through provider-neutral capabilities. Any required tip belongs in preparation, review, and signing; it remains payable if another route lands the transaction.

## Current implementation

- Create `TransactionCoordinator: TransactionCoordinating` once with `RPC` and `RecoveryStoring`. It delegates to internal `TransactionPreparing`, `TransactionSigning`, `TransactionSubmitting`, and `TransactionConfirming` services; callers don't assemble workflow helpers.
- `prepare(transfer, configuration:)` constructs a native SOL message with a confirmed blockhash and known block-height expiry.
- `prepare(transaction, for: signer)` accepts a typed `Transaction` from the import boundary, verifies existing signatures, and requires an empty slot for the selected account. `IsBlockhashValid` checks its original recent blockhash. It never replaces bytes or infers a network from them. Durable-nonce transactions remain unsupported.
- Import adapters use `TransactionDecoding` for binary or Base64 input; callers receive a typed `Transaction`. Preparation verifies its inspection agrees with the original message. Call sites never assemble envelopes or RPC options.
- Both paths share fee estimation and simulation using structured child tasks and the baseline context slot. Simulation skips signature verification to permit empty slots, never replaces the blockhash, and retains execution failures and unknown fees. RPC failures throw without retries; cancellation reaches pending operations.
- `Preparation` retains the source, selected signer, decoded transaction, network, fee, and simulation. Its message and envelope derive from that inspection. Account privileges and opaque instruction data are available for review; unknown programs aren't interpreted or declared safe.
- `PreparationValidator` shares the review, fee, and lifetime checks between signing and submission. After explicit approval, `sign(_:for:reason:)` revalidates the exact inspection, native construction intent where applicable, existing signatures, fee, network, and ledger contexts before protected recovery access. It checks lifetime before and after authentication: block height for local construction, original-blockhash validity for supplied bytes.
- `KeychainStore` owns authentication; `Wallet` checks that the recovered account matches the selected signer. Recovery remains local to signing. `SignedTransaction` contains a typed transaction, reports `isFullySigned`, and exposes its first signature when present; remaining empty slots can be returned to a requester for other signatures. No signing operation broadcasts.
- `submit(signed)` validates every required signature, preserves the reviewed message and existing signatures, then rechecks prerequisites. It performs one `SendTransaction` with confirmed preflight, the reviewed minimum slot, and zero node retries. `Submission` returns the expected signature and network only after a matching acknowledgment; it does not assert execution or confirmation.
- Submission errors retain provider diagnostics without retries. A timeout or cancellation after dispatch can leave receipt unknown; retain the signed result's locally known signature for status lookup rather than rebuilding or resigning automatically.
- `confirm(submission)` queries signature history with one-second delays until confirmed or finalized execution, returning `Confirmation` with the submission, execution slot, observed commitment, and `.succeeded` or `.failed(TransactionError)`. Missing, processed, and unspecified commitment remain unresolved. Network mismatches and malformed responses fail closed.
- Confirmation uses an injected Swift `Clock` and structured tasks with a 60-second deadline. Timeout and cancellation stop observation; neither proves failure, expiry, or non-delivery. RPC errors propagate without retrying. The service never rebuilds, resigns, or resubmits; callers may observe the same receipt again.
- Keep approval separate from authentication. Constructing a review value isn't proof of consent. Program-aware explanations and UI remain separate milestones.
- Verification: 32 app tests cover preparation, signing, typed submission/confirmation, preserved signatures, review tampering, expiry, provider errors, and cancellation. Confirmation timing uses a controlled clock without wall-time sleeps. Shared validation is tested once, with submission-specific boundary checks. Independent Kit fixtures use public recovery vectors; an alternate valid payer signature uses nonce scalar `r = 1`, with `S = (r + H(R || A || message) × a) mod L`, verified offline by Kit. Tests don't assume CryptoKit signatures are deterministic. Submission orchestration is verified offline; no new broadcast was performed for these milestones. Actual biometric enforcement retains the [Vault limits](wallet.md).
- Live devnet check (2026-09-27): the real RPC implementation accepted a newly fetched blockhash and rejected the zero hash at slot 504983023. Three read-only Helius calls; no transaction submitted. Earlier native-transfer simulations accepted 0.001 SOL and retained insufficient-funds diagnostics for 2 SOL.

- Live confirmation (2026-09-27): the real app service and Helius RPC, compiled in a disposable macOS harness, confirmed the earlier public devnet receipt as finalized and successful at slot `504928865` with one status request. No signing or broadcast; simulator tests cover the iOS integration.

```swift
let coordinator = TransactionCoordinator(rpc: rpc, store: recoveryStore)
let preparation = try await coordinator.prepare(transfer, configuration: configuration)
// Present the preparation and obtain explicit approval first.
let signed = try await coordinator.sign(preparation, for: walletID, reason: "Approve transaction")
let submission = try await coordinator.submit(signed)
let confirmation = try await coordinator.confirm(submission)
// Inspect confirmation.outcome: execution can be confirmed and still have failed.
```

For imported requests, replace preparation with `coordinator.prepare(importedTransaction, for: selectedAddress)`. Signing can still return its typed result to the requesting integration without submission.

Sources: [Apple protected Keychain access](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id.md), [Solana blockhash validity](https://solana.com/docs/rpc/http/isblockhashvalid), [block-height expiry](https://solana.com/developers/cookbook/transactions/confirmation), [submission semantics](https://solana.com/docs/rpc/http/sendtransaction), [signature status](https://solana.com/docs/rpc/http/getsignaturestatuses), [Swift Clock](https://developer.apple.com/documentation/swift/clock.md).
