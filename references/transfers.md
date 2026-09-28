# Transaction workflow

Internal app coordination follows [architecture](architecture.md). Services live under `widgets/Transactions`; app-hosted `widgetsTests` covers their behavior.

## Submission policy

- Include public Solana mainnet as a built-in provider. Submit through every supplied RPC on the transaction's network. One RPC receives one submission; multiple RPCs receive concurrent submissions.
- Submit the exact same signed transaction to every enabled provider on its network. Keep one signature and confirmation outcome; never rebuild or resign per provider.
- Attempt each route once. Retain independent errors so one failed provider does not cancel another submission. An acknowledgment establishes acceptance, not execution; dispatch failures can leave delivery unknown.
- Helius Sender is optional, with both tiers selectable in app settings. Its required tip belongs in preparation, review, and signing; it remains payable if another route lands the transaction.

## Current implementation

- Create `TransactionCoordinator: TransactionCoordinating` once with the read `RPC`, `RecoveryStoring`, and optional `[any RPC]` submission clients. Public Solana mainnet is the default client. Omitting the list uses the read client alone; an explicit list submits through every client on the transaction's network. Preparation and confirmation use the read client. No provider wrapper, DAS check, or portfolio dependency is involved.
- `prepare(transfer, configuration:)` constructs a native SOL message with a confirmed blockhash and known block-height expiry.
- Add `Sender(tier: .standard)` or `.premium` to the same RPC list. Its provider-neutral `submissionRequirements` supply a tip recipient, tip amount, and minimum priority fee. Native preparation includes the tip before simulation and exposes `preparation.tips` separately from the network fee. Fees below the requirement throw rather than increasing silently. Changing the tier requires new preparation and approval; settings UI remains later work.
- Standard maps to Helius SWQoS-only: a 5,000-lamport tip and a positive priority fee. Premium maps to Helius Max: a 1,000,000-lamport tip and a minimum 5,000-lamport priority fee. These are minimum bids, not landing guarantees. Tip recipients come from Helius's published list and stay stable for the client's lifetime.
- Sender uses the global HTTPS endpoint, with no API key, warming timer, or automatic retry. It is mainnet-only in this implementation; no Sender devnet endpoint is documented. Imported transactions retain their original instructions and signatures; Sender may reject them if its payment requirements are absent, while ordinary RPC attempts proceed independently.
- `prepare(transaction, for: signer)` accepts a typed `Transaction` from the import boundary, verifies existing signatures, and requires an empty slot for the selected account. `IsBlockhashValid` checks its original recent blockhash. It never replaces bytes or infers a network from them. Durable-nonce transactions remain unsupported.
- Import adapters use `TransactionDecoding` for binary or Base64 input; callers receive a typed `Transaction`. Preparation verifies its inspection agrees with the original message. Call sites never assemble envelopes or RPC options.
- Both paths share fee estimation and simulation using structured child tasks and the baseline context slot. Simulation skips signature verification to permit empty slots, never replaces the blockhash, and retains execution failures and unknown fees. RPC failures throw without retries; cancellation reaches pending operations.
- `Preparation` retains the source, selected signer, decoded transaction, network, fee, and simulation. Its message and envelope derive from that inspection. Account privileges and opaque instruction data are available for review; unknown programs aren't interpreted or declared safe.
- `PreparationValidator` shares the review, fee, and lifetime checks between signing and submission. After explicit approval, `sign(_:for:reason:)` revalidates the exact inspection, native construction intent where applicable, existing signatures, fee, network, and ledger contexts before protected recovery access. It checks lifetime before and after authentication: block height for local construction, original-blockhash validity for supplied bytes.
- `KeychainStore` owns authentication; `Wallet` checks that the recovered account matches the selected signer. Recovery remains local to signing. `SignedTransaction` contains a typed transaction, reports `isFullySigned`, and exposes its first signature when present; remaining empty slots can be returned to a requester for other signatures. No signing operation broadcasts.
- `submit(signed)` checks signatures and prerequisites once, then sends identical bytes through all supplied RPCs on the transaction's network in one structured task group, with confirmed preflight, the reviewed minimum slot, and zero node retries. It waits for the concurrent attempts to finish and returns a plain `Submission` if any acknowledges the expected signature. Consumers manage no delivery tasks.
- One RPC's error does not cancel another attempt. If none acknowledges, `Submitter.Rejection` retains every error, network, and locally known signature. Cancelling submission cancels its child requests. Dispatch failures and cancellation can leave delivery unknown; never rebuild or resign automatically.
- `confirm(submission)` queries signature history with one-second delays until confirmed or finalized execution, returning `Confirmation` with the submission, execution slot, observed commitment, and `.succeeded` or `.failed(TransactionError)`. Missing, processed, and unspecified commitment remain unresolved. Network mismatches and malformed responses fail closed.
- Confirmation uses an injected Swift `Clock` and structured tasks with a 60-second deadline. Timeout and cancellation stop observation; neither proves failure, expiry, or non-delivery. RPC errors propagate without retrying. The service never rebuilds, resigns, or resubmits; callers may observe the same receipt again.
- Keep approval separate from authentication. Constructing a review value isn't proof of consent. Program-aware explanations and UI remain separate milestones.
- Submission verification uses real Helius and public Solana devnet clients. The test runner reads `HELIUS_API_KEY` from ignored `Configuration/Local.xcconfig`. A fresh memory-only wallet requests faucet funding; if unavailable, its public address is printed for manual funding. The happy path submits one self-transfer and confirms its signature through both RPCs. The separate failure path submits from an unfunded wallet. Local signature guards use independent public vectors. Actual biometric enforcement retains the [Vault limits](wallet.md).
- Verification (2026-09-28): 45 Transactions tests and 30 app tests passed on iPhone Duo, including both Sender tiers' fee guards, devnet isolation, and real unfunded submissions through both RPCs. The funded submission test was excluded after unavailable faucets blocked its earlier setup; successful multi-submit remains unverified. Debug and Release builds passed.
- Sender check (2026-09-28): unsigned mainnet preparation through the actual service simulated both tiers successfully at slots 451386944–451386945, with separate tips of 5,000 and 1,000,000 lamports and a 10,000-lamport network fee for the chosen 5,000-lamport priority fee. Six read-only RPC calls; no signing or submission. Sender delivery remains unverified.
- Live devnet check (2026-09-27): the real RPC implementation accepted a newly fetched blockhash and rejected the zero hash at slot 504983023. Three read-only Helius calls; no transaction submitted. Earlier native-transfer simulations accepted 0.001 SOL and retained insufficient-funds diagnostics for 2 SOL.

- Live confirmation (2026-09-27): the real app service and Helius RPC, compiled in a disposable macOS harness, confirmed the earlier public devnet receipt as finalized and successful at slot `504928865` with one status request. No signing or broadcast; simulator tests cover the iOS integration.

```swift
let coordinator = TransactionCoordinator(rpc: rpc, store: recoveryStore,
    rpcs: [rpc, Solana(network: rpc.network)])
let preparation = try await coordinator.prepare(transfer, configuration: configuration)
// Present the preparation and obtain explicit approval first.
let signed = try await coordinator.sign(preparation, for: walletID, reason: "Approve transaction")
let submission = try await coordinator.submit(signed)
let confirmation = try await coordinator.confirm(submission)
// Inspect confirmation.outcome: execution can be confirmed and still have failed.
```

For imported requests, replace preparation with `coordinator.prepare(importedTransaction, for: selectedAddress)`. Signing can still return its typed result to the requesting integration without submission.

To enable Sender, append `Sender(tier: .standard)` or `Sender(tier: .premium)` to `rpcs` when creating the coordinator. Review `preparation.tips` alongside `preparation.fee`; the signing and submission calls stay the same.

Sender sources: [SWQoS-only](https://www.helius.dev/docs/sending-transactions/sender-swqos-only.md), [Max](https://www.helius.dev/docs/sending-transactions/sender-max.md), [request options](https://www.helius.dev/docs/api-reference/sender/sendtransaction.md), [Helius SDK V1 support](https://github.com/helius-labs/helius-rust-sdk/blob/dev/README.md).

Sources: [Apple protected Keychain access](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id.md), [Solana blockhash validity](https://solana.com/docs/rpc/http/isblockhashvalid), [block-height expiry](https://solana.com/developers/cookbook/transactions/confirmation), [submission semantics](https://solana.com/docs/rpc/http/sendtransaction), [signature status](https://solana.com/docs/rpc/http/getsignaturestatuses), [Swift Clock](https://developer.apple.com/documentation/swift/clock.md).
