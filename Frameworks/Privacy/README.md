# Privacy

Cryptography and instructions for Solana Rings private balances. It provides the Poseidon hash over the BN254 scalar field, built on [ModularArithmetic](../ModularArithmetic/README.md), the commitments of default-ring transfers, the encryption of their SOL notes, the shielded pool's deposit and transact instructions, as [Transactions](../Transactions/README.md) `Instruction` values, their proofs, and the notes an account receives. It reads registry records, indexer results, and proofs through [RPC](../RPC/README.md). Its public API is the account's registration and note sync: `ShieldedAccount`, `Registration`, `NoteSyncState`, `ReceivedNote`, and `ShieldedPool.networks`; the rest is internal to the module.

## Poseidon

[`Poseidon`](Sources/Poseidon/Poseidon.swift) is circom's x⁵ Poseidon over BN254, as light-poseidon v0.4.0 implements it:

- One to twelve inputs; the state is a zero domain tag followed by the inputs, a width t of 2 to 13. Other input counts throw `unsupportedInputCount`; the non-throwing variadic overload that commitments call traps instead, and each commitment passes one to seven inputs.
- 8 full rounds around 56 to 66 partial rounds, depending on t. The hash is the first element of the final state.
- Inputs are canonical field elements: 32 big-endian bytes below the modulus r, decoded with `FieldElement(bigEndianBytes:)`, which rejects other lengths and values at or above r.

## Parameters

- The round constants and MDS matrices are generated in Swift with the Grain LFSR method of hadeshash's [`generate_parameters_grain.sage`](https://extgit.isec.tugraz.at/krypto/hadeshash); no tables are copied.
- The hadeshash authors have deprecated that script. It is used because Solana Rings fixes circom's BN254 x⁵ parameters, and light-poseidon generated its tables with it.
- Each width's parameters are built on its first hash and kept for the rest of the process.
- Tests check the generated constants and matrices against the SHA-256 digests in zolana's Poseidon parity fixture, and hashes against all of its vectors.

## Commitments

The values that peer-to-peer transfers in the default (confidential) ring commit to. Owners are Ed25519 keys; UTXOs carry no UTXO data, ring data, or ring program, so P-256 and PDA owners and policy rings aren't supported.

- [`PackedBytes`](Sources/Commitments/PackedBytes.swift): `hash_bytes_32` and `hash_bytes_33`, which right-align 31-byte chunks in field elements and fold them with Poseidon, and the packing of up to 31 bytes into one field element, which the nullifier secret uses. The specification forbids a variable-length byte hash, so other lengths have no entry point.
- [`OwnerIdentity`](Sources/Commitments/OwnerIdentity.swift): a Solana owner's identity, `hash_bytes_33(0x53 ‖ signing public key)`, and its owner hash, `Poseidon(identity, nullifier public key)`.
- [`NullifierKey`](Sources/Commitments/NullifierKey.swift): the 31-byte nullifier secret, held in a CryptoKit `SymmetricKey`; its public key, `Poseidon(secret)`; and nullifiers, `Poseidon(UTXO hash, blinding, secret)`. Each hash zeroes the buffer that packs the secret's bytes; the field elements that Poseidon copies the secret into are never erased.
- [`UTXO`](Sources/Commitments/UTXO.swift): the hash `Poseidon(3, tree ID, hash_bytes_32(mint), amount, 0, Poseidon(0, 0), Poseidon(owner, blinding))`, with SOL's mint as 32 zero bytes, and the hash of the empty UTXO that pads unused input and output slots, `Poseidon(1, tree ID, 0, 0, 0, Poseidon(0, 0), Poseidon(0, blinding))`.
- [`TransactBlinding`](Sources/Commitments/TransactBlinding.swift): a transact proof's output blinding seed, output blindings, and private transaction blinding, derived from its blinding seed, its first nullifier, and the domain tags `TXOS`, `TXOB`, and `TXPB`.
- Tests check zolana's published vectors and the values of two SOL transfers in `hash_vectors.rs`. Edge cases that zolana doesn't publish come from an independent implementation.

## Encryption

The notes of confidential outputs in peer-to-peer default-ring transfers between users of this app. Only SOL, asset ID 1, is supported. CryptoKit supplies P-256 ECDH and HKDF-SHA256, and CommonCrypto supplies AES-256-CTR, which CryptoKit doesn't expose. Viewing keys and transaction viewing keys are CryptoKit `P256.KeyAgreement.PrivateKey` values.

- [`TransactionViewingKey`](Sources/Encryption/TransactionViewingKey.swift): the key that seals one transaction's notes. The view root is `HKDF-Extract(salt: empty, ECDH(viewing key, P_const))`, where `P_const` is RFC 9380's `P256_XMD:SHA-256_SSWU_RO_` hash of the empty message under `TSPP/view_root/P_const/v1`, pinned as a constant. The transaction viewing secret is `HKDF-Expand(view root, "TSPP/tx_viewing", 32)`, and the key's scalar is `HKDF(salt: first nullifier, secret, "TSPP/tx_viewing", 48)` modulo n.
- [`P256Scalar`](Sources/Encryption/P256Scalar.swift): the reduction of 48 big-endian bytes modulo n in ModularArithmetic's P-256 scalar field, as `low + high × (2^256 mod n)`. A zero scalar is rejected.
- [`SlotCipher`](Sources/Encryption/SlotCipher.swift): ECDH of the transaction viewing key and the recipient's viewing key, then `HKDF(salt: empty, shared ‖ transaction viewing public key ‖ recipient viewing public key, "TSPP/hpke/" ‖ "TSPP/tx" ‖ salt ‖ slot, 44)` for the AES key and a 12-byte nonce. The slot is the output's position, a big-endian 32-bit integer, and the counter block starts at `nonce ‖ 00 00 00 02`. Encryption and decryption are the same operation.
- [`ConfidentialPlaintext`](Sources/Encryption/ConfidentialPlaintext.swift): the 50-byte note: the asset ID and the amount as little-endian 64-bit integers, the canonical blinding, and zero bytes for no ring program and no data records. It holds the one mapping between asset IDs and mints.
- [`ConfidentialOutput`](Sources/Encryption/ConfidentialOutput.swift): the 89-byte payload of an output's data slot: the encoding tag 1, the little-endian 32-bit length of the rest, the scheme 3, the recipient's compressed viewing public key, and the ciphertext. Senders seal and reopen notes. A recipient opens only payloads that name its viewing key; zolana's sync ignores that key, which its senders always set to the recipient's. A recipient receives the UTXO only if the note decodes and the rebuilt hash equals the published one; any other output isn't the account's.
- The 58-byte transfer sender bundle in zolana's `spec.md` is stale; the module follows zolana's TypeScript and Rust code.
- Tests check zolana's `tx_viewing` and `hpke_utxo` vectors. Other values, including the payload of a published transfer's output, come from an independent implementation.

## Shielded pool

Instructions for zolana's shielded-pool program: a proofless deposit, and a transact that carries its proof. Both are SOL only, in the default ring, between Ed25519 owners. The program ID is zolana's development deployment. Instruction data is a one-byte tag followed by zolana's wincode encoding, which [`WincodeWriter`](Sources/ShieldedPool/WincodeWriter.swift) writes.

- [`ShieldedPool`](Sources/ShieldedPool/ShieldedPool.swift): the program, the SOL interface, `["sol_interface", [0]]`, each tree, `["tree", ID as little-endian u16]`, and each nullifier account, `["nullifier", tree, nullifier]`. `networks` lists where the programs exist: devnet only.
- [`Recipient`](Sources/ShieldedPool/Recipient.swift): a shielded address's signing address, which is also its view tag, nullifier public key, and viewing public key, and its owner hash. Off-curve signing addresses are rejected, because no key could spend their UTXOs.
- [`ShieldedPool+Deposit`](Sources/ShieldedPool/ShieldedPool+Deposit.swift): `deposit`, tag 15, of public SOL into one recipient's UTXO. The program derives the UTXO's blinding.
- [`TransactPlan`](Sources/Transact/TransactPlan.swift): a SOL transact before its proof, after zolana's `ConfidentialTransaction` with random padding. It spends at most 40 of the sender's UTXOs, zolana's wallet limit, from at most two trees, into a transfer, a withdrawal, or both, and change; picks the cheapest of the 38 supported [`Shape`](Sources/Transact/Shape.swift)s; pads inputs and outputs with empty UTXOs; derives the output blindings; and seals each real output's note. Randomness comes from an injected `RandomNumberGenerator`.
- [`ExternalData`](Sources/Transact/ExternalData.swift): the instruction's prefix that the proof commits to, with no expiry, and its hash: SHA-256 of the tag 16, the prefix, the withdrawal's SOL interface and recipient, and the payer once for each output that refers to it, with the first byte set to zero. [`TransactOutput`](Sources/Transact/TransactOutput.swift) writes each output with its view tag inline or as a reference to the payer.
- [`PrivateTransactionHash`](Sources/Transact/PrivateTransactionHash.swift): `Poseidon(chain(inputs), chain(outputs), 0, blinding)` with zolana's nonzero hash chain; padding slots enter as zero, and no addresses are created.
- [`TransactPlan.instruction(proof:treeContexts:)`](Sources/Transact/TransactPlan+Instruction.swift): `transact`, tag 16, with the [`TransactProof`](Sources/Transact/TransactProof.swift) and one [`TreeContext`](Sources/Transact/TreeContext.swift) per input tree. The sender pays the fee and signs; the proof binds the payer, not the blockhash.
- [`UserRegistry`](Sources/ShieldedPool/UserRegistry.swift): an owner's record, `["zolana/registry/v0", owner]` under the user-registry program, decoded into a `Recipient`; a missing account, or one that the program doesn't own, means the owner hasn't registered. Lookups read up to 100 records with one finalized `getMultipleAccounts`. P-256 owners are rejected.
- Policy rings, tokens, merges, and compact padding aren't supported.
- Tests check zolana's nullifier account vector, the nonzero hash chain and private transaction hash vectors, and the external data and private transaction hashes of the two transfers in `hash_vectors.rs`, with every output's note. The transfers' recipient keys, the tree addresses, and whole deposit and transact instructions, which zolana doesn't publish, come from an independent implementation.

## Proofs

A transfer proof's one public input hashes 18 field elements; the prover receives the 17 that don't depend on the tree roots, resolves the roots from its own indexer, and inserts the tree slots' chain at index 2.

- [`HashChain`](Sources/Proof/HashChain.swift): the left and right chains of three-element groups, the binary right chain, and chains of zeros.
- [`InputFlags`](Sources/Proof/InputFlags.swift): padding inputs allowed in bit 0, and each input's tree position in three bits from bit `1 + 3i`. The program clears bit 0 when a tree runs low on room for padding nullifiers, which rejects such a proof.
- [`PublicInputs`](Sources/Proof/PublicInputs.swift): the statement and its hash; [`TransactPlan.publicInputs`](Sources/Transact/TransactPlan+PublicInputs.swift) fills it from a plan: the payer as the only signer, SOL's asset and `r - lamports` in public slot 0 for a withdrawal, and each output tag's identity.
- [`TransactPlan+Proof`](Sources/Transact/TransactPlan+Proof.swift): the request on the prover's indexed route, with the witness, which holds the nullifier secret and the blinding seed in plain form; and the checks of the response: the shape's proving-key digest, from zolana's lock file in [`Shape+ProvingKey`](Sources/Proof/Shape+ProvingKey.swift); the declared trees in order; root positions inside their histories, 500 UTXO roots and 100 nullifier roots; and the public input hash recomputed from the resolved roots. [`ProofPoint`](Sources/Proof/ProofPoint.swift) negates and compresses `a` and compresses `c`.
- No Groth16 pairing runs on the device, since Apple's frameworks have no BN254 pairing. A proof that doesn't verify fails the transaction's simulation with program error 7008 and can't move funds.
- Tests check zolana's chain, input-flag, public-input, and proving-key vectors and its assembled transfer. Whole requests, responses with random curve points, registry records, and deposits, which zolana doesn't publish, come from an independent implementation.

## Notes

- [`ShieldedAccount`](Sources/ShieldedPool/ShieldedAccount.swift): an account's signing address, nullifier key, and viewing key, from Wallet's `PrivateBalanceKeys`. It spends a transact plan's inputs and receives notes. Descriptions and reflection omit every value.
- [`Registration`](Sources/ShieldedPool/Registration.swift): an account's registry record, read with one `getMultipleAccounts` through any provider: `unregistered`, `registered` when the record's nullifier public key and compressed viewing public key are the account's, or `registeredWithOtherKeys`. A malformed record throws.
- [`ReceivedNote`](Sources/Notes/ReceivedNote.swift): an account's UTXOs in the indexer's transactions, with their nullifiers. Confidential outputs tagged with the account's signing address are opened with its viewing key. Proofless deposits, [`ProoflessOutput`](Sources/Notes/ProoflessOutput.swift), publish the UTXO in the clear; the account checks its owner hash, SOL, the blinding that [`ShieldedPool.depositBlinding`](Sources/ShieldedPool/ShieldedPool+Deposit.swift) derives from the tree and the leaf index, and the published hash. Outputs that fail any check belong to someone else. Notes encode their fields with field elements as 32 big-endian bytes; decoding rejects other lengths, non-canonical values, and mints other than SOL's.
- [`NoteSyncState`](Sources/Notes/NoteSyncState.swift): an account's unspent SOL notes, their total in lamports, and the indexer position, stored by the caller. `synced(for:using:)` reads the account's tagged transactions after the position and the current notes' spends concurrently, adds new notes once by nullifier, and, as soon as the tagged transactions arrive, reads the spends of the new notes they don't spend. It drops notes whose nullifiers any returned transaction publishes, sends no spend read without notes, and fails on the first error, which cancels the other reads. It returns a new state and leaves the old one unchanged on error. Totals above a 64-bit integer throw. Token notes don't decode, so a release that adds tokens syncs again from an empty state.

## Side channels

The rounds depend only on the number of inputs. Field arithmetic follows ModularArithmetic's [side-channel note](../ModularArithmetic/README.md#side-channels). The scalar reduction branches only to reject a zero scalar. Encryption zeroes the buffers that it fills with key material, scalars, and counter blocks; CryptoKit and CommonCrypto hold the other copies of keys and shared secrets; the view root and the field elements of the scalar reduction aren't erased.

## Sources

| Source | Version | Used for |
| --- | --- | --- |
| [Solana Rings](https://www.helius.dev/docs/privacy) by Helius, specified in zolana's [`spec.md`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/docs/spec.md) | v0.4.0-alpha | The private-balance protocol this module implements |
| zolana's TypeScript [hasher](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/sdk-libs/ts/src/hasher) | v0.4.0-alpha | Reference for the hash the protocol uses; read, never run |
| zolana's TypeScript [keypair](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/sdk-libs/ts/src/keypair) and [transaction](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/sdk-libs/ts/src/transaction) sources, and Rust [keypair tests](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/sdk-libs/keypair/tests) | v0.4.0-alpha | Reference for the commitments and the encryption; read, never run |
| zolana's [test vectors](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/test-vectors) `hash_bytes.json`, `transact_derivation.json`, and `key_derivation.json` (Apache-2.0) | v0.4.0-alpha | Commitment and encryption test vectors; sections copied unchanged |
| zolana's TypeScript tests [`seed-based-keypair.test.ts`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/ts/test/seed-based-keypair.test.ts) and [`ring-policy.test.ts`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/ts/test/ring-policy.test.ts) (Apache-2.0) | v0.4.0-alpha | Owner-hash and nullifier test values, copied unchanged |
| zolana's Rust test [`hash_vectors.rs`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/transaction/tests/hash_vectors.rs) (Apache-2.0) | v0.4.0-alpha | UTXO-hash, nullifier, blinding, external data hash, and private transaction hash test values of two transfers, copied unchanged |
| zolana's [interface](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/program-libs/interface/src), [shielded-pool accounts](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/programs/shielded-pool/src/instructions), and Rust [transact builder](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/sdk-libs/transaction/src/instructions/transact) | v0.4.0-alpha | Reference for the instructions, their accounts, and the transact plan; read, never run |
| zolana's [test vectors](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/test-vectors) `private_tx_hash.json` and `nonzero_hash_chain.json`, and the nullifier account vector of `program-libs/interface/tests/pda.rs` (Apache-2.0) | v0.4.0-alpha | Hash and address test vectors, copied unchanged |
| zolana's [Poseidon parity fixture](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/ts/vectors/poseidon-parity-v1.json) (Apache-2.0) | v0.4.0-alpha | Test digests and vectors, copied unchanged |
| zolana's [test vectors](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/test-vectors) `hash_chain_4.json`, `right_hash_chain_4.json`, `input_flags.json`, `public_input_hash.json`, and the `tree_slots` section of `transact_derivation.json`; [`indexed-proof.json`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/fixtures/indexed-proof.json); and the values of `assembly_vectors.rs` and `deposit.rs` (Apache-2.0) | v0.4.0-alpha | Proof input test vectors, copied unchanged |
| zolana's [`proving-keys.lock`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/prover/server/prover/provingkeys/proving-keys.lock) (Apache-2.0) | v0.4.0-alpha | The proving-key digests, copied into the source and unchanged into a test fixture |
| zolana's Rust [prover client](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/sdk-libs/client/src/prover), [user registry](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/program-libs/user-registry-interface), and [proofless output](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/program-libs/event/src/proofless.rs) | v0.4.0-alpha | Reference for the proof request, its checks, registry records, and deposits; read, never run |
| [light-poseidon](https://github.com/Lightprotocol/light-poseidon/tree/v0.4.0) | 0.4.0 | Round structure and partial-round counts |
| hadeshash's [`generate_parameters_grain.sage`](https://extgit.isec.tugraz.at/krypto/hadeshash) | — | Grain LFSR method for the constants and matrices |
| [Poseidon: A New Hash Function for Zero-Knowledge Proof Systems](https://eprint.iacr.org/2019/458) | USENIX Security 2021 | The hash design |
| [RFC 9380](https://www.rfc-editor.org/rfc/rfc9380), Hashing to Elliptic Curves | — | `P_const`'s hash to curve and the 48-byte scalar reduction |
| [RFC 5869](https://www.rfc-editor.org/rfc/rfc5869), HKDF | — | Key derivation of the encryption |

Solana Rings is in beta, and its releases can change parameters, vectors, and hashing rules; v0.4.0-alpha stopped earlier clients from working. Check this module against every new zolana or light-poseidon release before updating these versions.
