# Privacy

Solana Rings private balances: an account's registration, its received notes, deposits, and private transfers and withdrawals with their proofs. Instructions are [Transactions](../Transactions/README.md) values, and reads go through [RPC](../RPC/README.md).

## Usage

```swift
import Privacy
import RPC
import Transactions

let account = try ShieldedAccount(
    signingAddress: Address(address),
    nullifierSecret: keys.nullifierSecret,
    viewingKey: keys.viewingKey
)
let registration = try await account.registration(using: rpc)
let notes = try await NoteSyncState().synced(for: account, using: helius)
```

`keys` comes from Wallet's `privateBalanceKeys`. `ShieldedAccount.register(paidBy:)` and `ShieldedPool.deposit` make instructions, and `NoteSyncState.spend` makes a proved private transfer.

## Sources

| Source | Version | Used for |
| --- | --- | --- |
| [Solana Rings](https://www.helius.dev/docs/privacy) by Helius, specified in zolana's [`spec.md`](https://github.com/helius-labs/zolana/blob/bb2337f05317aa245a345f47c68e434ffed62561/docs/spec.md) | 0.7.0-alpha | The private-balance protocol this module implements |
| zolana's TypeScript [hasher](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/sdk-libs/ts/src/hasher) | v0.4.0-alpha | Reference for the hash the protocol uses; read, never run |
| zolana's TypeScript [keypair](https://github.com/helius-labs/zolana/tree/bb2337f05317aa245a345f47c68e434ffed62561/sdk-libs/ts/src/keypair) and [transaction](https://github.com/helius-labs/zolana/tree/bb2337f05317aa245a345f47c68e434ffed62561/sdk-libs/ts/src/transaction) sources, and Rust [keypair tests](https://github.com/helius-labs/zolana/tree/bb2337f05317aa245a345f47c68e434ffed62561/sdk-libs/keypair/tests) | 0.7.0-alpha | Reference for the commitments and the encryption; read, never run |
| zolana's [test vectors](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/test-vectors) `hash_bytes.json` and `transact_derivation.json` (Apache-2.0) | v0.4.0-alpha | Commitment test vectors; sections copied unchanged |
| zolana's [test vectors](https://github.com/helius-labs/zolana/tree/bb2337f05317aa245a345f47c68e434ffed62561/test-vectors) `key_derivation.json` (Apache-2.0) | 0.7.0-alpha | Key and encryption test vectors; sections copied unchanged |
| zolana's TypeScript tests [`seed-based-keypair.test.ts`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/ts/test/seed-based-keypair.test.ts) and [`ring-policy.test.ts`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/ts/test/ring-policy.test.ts) (Apache-2.0) | v0.4.0-alpha | Owner-hash and nullifier test values, copied unchanged |
| zolana's Rust test [`hash_vectors.rs`](https://github.com/helius-labs/zolana/blob/bb2337f05317aa245a345f47c68e434ffed62561/sdk-libs/transaction/tests/hash_vectors.rs) (Apache-2.0) | 0.7.0-alpha | UTXO-hash, nullifier, blinding, external data hash, and private transaction hash test values of two transfers, copied unchanged |
| zolana's [interface](https://github.com/helius-labs/zolana/tree/bb2337f05317aa245a345f47c68e434ffed62561/program-libs/interface/src), [shielded-pool accounts](https://github.com/helius-labs/zolana/tree/bb2337f05317aa245a345f47c68e434ffed62561/programs/shielded-pool/src/instructions), and Rust [transact builder](https://github.com/helius-labs/zolana/tree/bb2337f05317aa245a345f47c68e434ffed62561/sdk-libs/transaction/src/instructions/transact) | 0.7.0-alpha | Reference for the instructions, their accounts, and the transact plan; read, never run |
| zolana's [test vectors](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/test-vectors) `private_tx_hash.json` and `nonzero_hash_chain.json` (Apache-2.0) | v0.4.0-alpha | Hash test vectors, copied unchanged |
| zolana's nullifier account vector in [`pda.rs`](https://github.com/helius-labs/zolana/blob/bb2337f05317aa245a345f47c68e434ffed62561/program-libs/interface/tests/pda.rs) (Apache-2.0) | 0.7.0-alpha | Address test vector, copied unchanged |
| zolana's [Poseidon parity fixture](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/ts/vectors/poseidon-parity-v1.json) (Apache-2.0) | v0.4.0-alpha | Test digests and vectors, copied unchanged |
| zolana's [test vectors](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/test-vectors) `hash_chain_4.json`, `right_hash_chain_4.json`, `input_flags.json`, `public_input_hash.json`, and the `tree_slots` section of `transact_derivation.json`; [`indexed-proof.json`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/fixtures/indexed-proof.json); and the values of `assembly_vectors.rs` and `deposit.rs` (Apache-2.0) | v0.4.0-alpha | Proof input test vectors, copied unchanged |
| zolana's [`proving-keys.lock`](https://github.com/helius-labs/zolana/blob/bb2337f05317aa245a345f47c68e434ffed62561/prover/server/prover/provingkeys/proving-keys.lock) (Apache-2.0) | 0.7.0-alpha | The proving-key digests, copied into the source and unchanged into a test fixture |
| zolana's Rust [prover client](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/sdk-libs/client/src/prover) and [proofless output](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/program-libs/event/src/proofless.rs) | v0.4.0-alpha | Reference for the proof request, its checks, and deposits; read, never run |
| zolana's Rust [user registry](https://github.com/helius-labs/zolana/tree/bb2337f05317aa245a345f47c68e434ffed62561/program-libs/user-registry-interface) | 0.7.0-alpha | Reference for registry records; read, never run |
| zolana's prover [`TransferParametersJSON`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/prover/server/prover/transfer_eddsa_only/marshal.go) and [indexer API](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/indexer-api/src/lib.rs) | v0.4.0-alpha | Reference for the complete-route request and the Merkle and non-inclusion proof reads; read, never run |
| zolana's [`dummy_owner_tags.json`](https://github.com/helius-labs/zolana/blob/f163d0f0c824381a7a6ebf8701bff1e8266aee7e/test-vectors/dummy_owner_tags.json) (Apache-2.0) | main at f163d0f | Padding owner tag test vectors, copied unchanged |
| [light-poseidon](https://github.com/Lightprotocol/light-poseidon/tree/v0.4.0) | 0.4.0 | Round structure and partial-round counts |
| hadeshash's [`generate_parameters_grain.sage`](https://extgit.isec.tugraz.at/krypto/hadeshash) | — | Grain LFSR method for the constants and matrices |
| [Poseidon: A New Hash Function for Zero-Knowledge Proof Systems](https://eprint.iacr.org/2019/458) | USENIX Security 2021 | The hash design |
| [RFC 5869](https://www.rfc-editor.org/rfc/rfc5869), HKDF | — | Key derivation of the encryption |
