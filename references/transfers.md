# Transaction workflow

Internal app coordination follows [architecture](architecture.md). Services live under `widgets/Transactions`; app-hosted `widgetsTests` covers their behavior.

## Submission policy

- Include public Solana mainnet as a built-in provider. Choose one strategy: `none` (the default), `standard`, or `premium`.
- `none` submits concurrently through configured ordinary RPCs on the transaction's network. `standard` and `premium` submit only through the selected Sender tier. No simultaneous ordinary-RPC broadcast or automatic fallback accompanies Sender.
- Submit the exact same signed transaction to the selected clients. Keep one signature and confirmation outcome; never rebuild or resign per provider.
- Attempt each route once. Retain independent errors so one failed provider does not cancel another submission. An acknowledgment establishes acceptance, not execution; dispatch failures can leave delivery unknown.
- Sender's required tip belongs in preparation, review, and signing. Disabling Sender adds no service tip; imported instructions remain unchanged.

## Current implementation

- Create `TransactionCoordinator: TransactionCoordinating` with the read `RPC`, `RecoveryStoring`, optional ordinary `rpcs`, and `strategy: .none`. Its internal `Strategy` selects the same clients for preparation and submission. With `.none`, omitting `rpcs` uses the read client alone; service-payment clients and other networks are excluded. Sender modes replace the list with one Sender client. Initialization throws `Submitter.Failure.noProviders` when no route matches the read network, including Sender on devnet. Preparation and confirmation retain the read RPC; DAS stays outside this workflow.
- `prepare(transfer, configuration:)` constructs a native SOL message with a confirmed blockhash and known block-height expiry.
- `prepareTokenTransfer(mint:amount:from:to:configuration:)` discovers the token program and associated accounts. Optional `source` selects a non-associated account; `memo` supplies incoming-memo requirements. The mint and both accounts are reread together, followed by the Token-2022 epoch when applicable and a fresh blockhash, with nondecreasing confirmed context slots. Preparation exposes `tokenTransfer` with the raw debit, expected token fee, and destination-creation requirement. Rent remains separate and unestimated; do not present `fee` as the total SOL debit.
- Token preparation includes the strategy's SOL tips before fee estimation and simulation. Signing and submission reconstruct the exact token intent and tips before protected wallet access or broadcast. Account state can change after review; checked instructions and preflight enforce current on-chain requirements.
- Set `strategy: .standard` or `.premium` to select Sender internally. Its provider-neutral `submissionRequirements` supply a tip recipient, tip amount, and minimum priority fee. Native preparation includes the tip before simulation and exposes `preparation.tips` separately from the network fee. Fees below the requirement throw rather than increasing silently. Changing strategy creates a new coordinator and requires new preparation and approval; settings UI remains later work.
- Standard maps to Helius SWQoS-only: a 5,000-lamport tip and a positive priority fee. Premium maps to Helius Max: a 1,000,000-lamport tip and a minimum 5,000-lamport priority fee. These are minimum bids, not landing guarantees. Tip recipients come from Helius's published list and stay stable for the client's lifetime.
- Sender uses the global HTTPS endpoint, with no API key, warming timer, or automatic retry. It is mainnet-only in this implementation; no Sender devnet endpoint is documented. Imported transactions retain their original instructions and signatures; Sender may reject them if its payment requirements are absent. That failure never triggers ordinary-RPC fallback.
- `prepare(transaction, for: signer)` accepts a typed `Transaction` from the import boundary, verifies existing signatures, and requires an empty slot for the selected account. `IsBlockhashValid` checks its original recent blockhash. It never replaces bytes or infers a network from them. Durable-nonce transactions remain unsupported.
- Import adapters use `TransactionDecoding` for binary or Base64 input; callers receive a typed `Transaction`. Preparation verifies its inspection agrees with the original message. Call sites never assemble envelopes or RPC options.
- All preparation paths share fee estimation and simulation using structured child tasks and the baseline context slot. Simulation skips signature verification to permit empty slots, never replaces the blockhash, and retains execution failures and unknown fees. RPC failures throw without retries; cancellation reaches pending operations.
- `Preparation` retains the source, selected signer, decoded transaction, network, fee, and simulation. Its message and envelope derive from that inspection. Account privileges and opaque instruction data are available for review; unknown programs aren't interpreted or declared safe.
- `PreparationValidator` shares the review, fee, and lifetime checks between signing and submission. After explicit approval, `sign(_:for:reason:)` revalidates the exact inspection, local SOL or token intent where applicable, existing signatures, fee, network, and ledger contexts before protected recovery access. It checks lifetime before and after authentication: block height for local construction, original-blockhash validity for supplied bytes.
- `KeychainStore` owns authentication; `Wallet` checks that the recovered account matches the selected signer. Recovery remains local to signing. `SignedTransaction` contains a typed transaction, reports `isFullySigned`, and exposes its first signature when present; remaining empty slots can be returned to a requester for other signatures. No signing operation broadcasts.
- `submit(signed)` checks signatures and prerequisites once, then sends identical bytes through the strategy's selected clients in one structured task group, with confirmed preflight, the reviewed minimum slot, and zero node retries. It waits for these attempts to finish and returns a plain `Submission` if any acknowledges the expected signature. Sender strategies wait only for Sender; consumers manage no delivery tasks.
- One RPC's error does not cancel another attempt. If none acknowledges, `Submitter.Rejection` retains every error, network, and locally known signature. Cancelling submission cancels its child requests. Dispatch failures and cancellation can leave delivery unknown; never rebuild or resign automatically.
- `confirm(submission)` queries signature history with one-second delays until confirmed or finalized execution, returning `Confirmation` with the submission, execution slot, observed commitment, and `.succeeded` or `.failed(TransactionError)`. Missing, processed, and unspecified commitment remain unresolved. Network mismatches and malformed responses fail closed.
- Confirmation uses an injected Swift `Clock` and structured tasks with a 60-second deadline. Timeout and cancellation stop observation; neither proves failure, expiry, or non-delivery. RPC errors propagate without retrying. The service never rebuilds, resigns, or resubmits; callers may observe the same receipt again.
- Keep approval separate from authentication. Constructing a review value isn't proof of consent. Program-aware explanations and UI remain separate milestones.
- Submission verification uses real Helius and public Solana devnet clients with `HELIUS_API_KEY` from ignored `Configuration/Local.xcconfig`. Both funded test wallets are saved and read back through Vault before funding, retain stable identities across runs, and reuse existing balances. The test sends 0.001 SOL, verifies the recipient balance through both RPCs, and returns the amount minus its return fee. Lost protection or changed identity stops setup. The separate failure path uses an unfunded disposable wallet. Actual biometric enforcement retains the [Vault limits](wallet.md).
- Verification (2026-09-28): 47 Transactions tests and 35 app regression tests passed on iPhone Duo, including live devnet preparation for both token programs; two opt-in biometric tests were verified separately. The funded SOL test passed twice across process restarts, sending 0.001 SOL and returning it after fees through retained wallets, with no further funding on the second run. Debug and Release builds passed. Token broadcasting and Sender delivery remain unverified.
- Sender check (2026-09-28): unsigned mainnet preparation through the actual service simulated both tiers successfully at slots 451386944–451386945, with separate tips of 5,000 and 1,000,000 lamports and a 10,000-lamport network fee for the chosen 5,000-lamport priority fee. Six read-only RPC calls; no signing or submission. Sender delivery remains unverified.
- Live devnet check (2026-09-27): the real RPC implementation accepted a newly fetched blockhash and rejected the zero hash at slot 504983023. Three read-only Helius calls; no transaction submitted. Earlier native-transfer simulations accepted 0.001 SOL and retained insufficient-funds diagnostics for 2 SOL.

- Live confirmation (2026-09-27): the real app service and Helius RPC, compiled in a disposable macOS harness, confirmed the earlier public devnet receipt as finalized and successful at slot `504928865` with one status request. No signing or broadcast; simulator tests cover the iOS integration.

```swift
let coordinator = try TransactionCoordinator(rpc: rpc, store: recoveryStore,
    rpcs: [rpc, Solana(network: rpc.network)], strategy: .none)
let preparation = try await coordinator.prepare(transfer, configuration: configuration)
// Present the preparation and obtain explicit approval first.
let signed = try await coordinator.sign(preparation, for: walletID, reason: "Approve transaction")
let submission = try await coordinator.submit(signed)
let confirmation = try await coordinator.confirm(submission)
// Inspect confirmation.outcome: execution can be confirmed and still have failed.
```

For imported requests, replace preparation with `coordinator.prepare(importedTransaction, for: selectedAddress)`. Signing can still return its typed result to the requesting integration without submission.

For either token program, use `coordinator.prepareTokenTransfer(mint: mint, amount: rawUnits, from: sender, to: recipient, configuration: configuration)`. The remaining review, signing, submission, and confirmation calls are the same.

To enable Sender, change `strategy` to `.standard` or `.premium`; the coordinator selects its exclusive route. Review `preparation.tips` alongside `preparation.fee`; the signing and submission calls stay the same.

Sender sources: [SWQoS-only](https://www.helius.dev/docs/sending-transactions/sender-swqos-only.md), [Max](https://www.helius.dev/docs/sending-transactions/sender-max.md), [request options](https://www.helius.dev/docs/api-reference/sender/sendtransaction.md), [Helius SDK V1 support](https://github.com/helius-labs/helius-rust-sdk/blob/dev/README.md).

Sources: [Apple protected Keychain access](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id.md), [Solana blockhash validity](https://solana.com/docs/rpc/http/isblockhashvalid), [block-height expiry](https://solana.com/developers/cookbook/transactions/confirmation), [submission semantics](https://solana.com/docs/rpc/http/sendtransaction), [signature status](https://solana.com/docs/rpc/http/getsignaturestatuses), [Swift Clock](https://developer.apple.com/documentation/swift/clock.md).
