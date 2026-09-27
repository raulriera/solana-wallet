# Transactions

- `MessageBuilder` implements `MessageBuilding` for local, single-instruction V1 SOL transfers. `Transfer` supplies validated `Address` values and positive `UInt64` lamports; the sender pays fees.
- Supply a recent blockhash and explicit `Configuration`: total priority-fee lamports, compute units, and loaded-account bytes. Optional heap size defaults to the protocol's 32 KiB. Limits are validated, never silently clamped; simulation must establish sufficiency.
- `message(for:recentBlockhash:configuration:)` returns `Data` for `GetFeeForMessage` and future signing. Simulation/submission need a complete transaction, including trailing V1 signatures; message bytes alone are insufficient.
- The shared [Encoding](encoding.md) codec supplies strict Base58; Transactions requests exactly 32 bytes for addresses and blockhashes. Self-transfers reuse the signer index. The invoked System Program cannot be a transfer account.
- Construction is synchronous, bounded, and stateless; values are `Sendable`. No recovery material, networking, signing, or UI belongs in this milestone. Encoding validation doesn't establish account existence, available funds, or blockhash freshness.
- Nine focused Swift Testing tests cover independent wire fixtures and meaningful invalid inputs. Fixtures use the public accounts in Solana's [V1 examples](https://github.com/solana-foundation/transaction-v1-examples/blob/main/ts/kit/test/wire.test.ts), generated offline with `@solana/kit` 8.0.0 and `@solana-program/system` 0.13.0: construct the transfer, apply each fixture's config/lifetime, then Base64-encode `compileTransaction(message).messageBytes`. Neither package is an app or test dependency.

Sources: [V1 wire format](https://github.com/solana-foundation/solana-improvement-documents/blob/main/proposals/0385-transaction-v1.md), [runtime resource bounds](https://github.com/anza-xyz/agave/blob/master/program-runtime/src/execution_budget.rs).
