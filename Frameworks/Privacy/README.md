# Privacy

Cryptography for Solana Rings private balances. It provides the Poseidon hash over the BN254 scalar field, built on [ModularArithmetic](../ModularArithmetic/README.md), the commitments of default-ring transfers, and the encryption of their SOL notes. Its API is internal to the module.

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
| zolana's Rust test [`hash_vectors.rs`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/transaction/tests/hash_vectors.rs) (Apache-2.0) | v0.4.0-alpha | UTXO-hash, nullifier, and blinding test values of two transfers, copied unchanged |
| zolana's [Poseidon parity fixture](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/ts/vectors/poseidon-parity-v1.json) (Apache-2.0) | v0.4.0-alpha | Test digests and vectors, copied unchanged |
| [light-poseidon](https://github.com/Lightprotocol/light-poseidon/tree/v0.4.0) | 0.4.0 | Round structure and partial-round counts |
| hadeshash's [`generate_parameters_grain.sage`](https://extgit.isec.tugraz.at/krypto/hadeshash) | — | Grain LFSR method for the constants and matrices |
| [Poseidon: A New Hash Function for Zero-Knowledge Proof Systems](https://eprint.iacr.org/2019/458) | USENIX Security 2021 | The hash design |
| [RFC 9380](https://www.rfc-editor.org/rfc/rfc9380), Hashing to Elliptic Curves | — | `P_const`'s hash to curve and the 48-byte scalar reduction |
| [RFC 5869](https://www.rfc-editor.org/rfc/rfc5869), HKDF | — | Key derivation of the encryption |

Solana Rings is in beta, and its releases can change parameters, vectors, and hashing rules; v0.4.0-alpha stopped earlier clients from working. Check this module against every new zolana or light-poseidon release before updating these versions.
