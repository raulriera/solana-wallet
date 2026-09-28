# Transaction workflow

Internal app coordination follows [architecture](architecture.md). Services live under `widgets/Transactions`; app-hosted `widgetsTests` covers their behavior.

- Create `TransactionCoordinator: TransactionCoordinating` once with `RPC` and `RecoveryStoring`. It delegates to internal `TransactionPreparing` and `TransactionSigning` services; callers don't assemble workflow helpers.
- `prepare(transfer, configuration:)` constructs a native SOL message with a confirmed blockhash and known block-height expiry.
- `prepare(transaction, for: signer)` accepts a typed `Transaction` from the import boundary, verifies existing signatures, and requires an empty slot for the selected account. `IsBlockhashValid` checks its original recent blockhash. It never replaces bytes or infers a network from them. Durable-nonce transactions remain unsupported.
- Import adapters use `TransactionDecoding` for binary or Base64 input; callers receive a typed `Transaction`. Preparation verifies its inspection agrees with the original message. Call sites never assemble envelopes or RPC options.
- Both paths share fee estimation and simulation using structured child tasks and the baseline context slot. Simulation skips signature verification to permit empty slots, never replaces the blockhash, and retains execution failures and unknown fees. RPC failures throw without retries; cancellation reaches pending operations.
- `Preparation` retains the source, selected signer, decoded transaction, network, fee, and simulation. Its message and envelope derive from that inspection. Account privileges and opaque instruction data are available for review; unknown programs aren't interpreted or declared safe.
- `PreparationValidator` encapsulates the review, fee, and lifetime checks for signing. After explicit approval, `sign(_:for:reason:)` revalidates the exact inspection, native construction intent where applicable, existing signatures, fee, network, and ledger contexts before protected recovery access. It checks lifetime before and after authentication: block height for local construction, original-blockhash validity for supplied bytes.
- `KeychainStore` owns authentication; `Wallet` checks that the recovered account matches the selected signer. Recovery remains local to signing. `SignedTransaction` contains a typed transaction, reports `isFullySigned`, and exposes its first signature when present; remaining empty slots can be returned to a requester for other signatures. No signing operation broadcasts.
- Keep approval separate from authentication. Constructing a review value isn't proof of consent. Submission, confirmation coordination, program-aware explanations, and UI remain separate milestones.
- Verification: 18 app tests cover preparation, signing, preserved signatures, review tampering, expiry, errors, and cancellation. Independent Kit fixtures use public recovery vectors. Tests verify CryptoKit signatures rather than assuming deterministic bytes. Actual biometric enforcement retains the [Vault limits](wallet.md).
- Live devnet check (2026-09-27): the real RPC implementation accepted a newly fetched blockhash and rejected the zero hash at slot 504983023. Three read-only Helius calls; no transaction submitted. Earlier native-transfer simulations accepted 0.001 SOL and retained insufficient-funds diagnostics for 2 SOL.

```swift
let coordinator = TransactionCoordinator(rpc: rpc, store: recoveryStore)
let preparation = try await coordinator.prepare(transfer, configuration: configuration)
// Present the preparation and obtain explicit approval first.
let signed = try await coordinator.sign(preparation, for: walletID, reason: "Approve transaction")
```

For imported requests, replace preparation with `coordinator.prepare(importedTransaction, for: selectedAddress)`. Signing can still return its typed result to the requesting integration without submission.

Sources: [Apple protected Keychain access](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id.md), [Solana blockhash validity](https://solana.com/docs/rpc/http/isblockhashvalid), [block-height expiry](https://solana.com/developers/cookbook/transactions/confirmation).
