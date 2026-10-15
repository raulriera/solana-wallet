# Privacy

Cryptography for Solana Rings private balances. It provides the Poseidon hash over the BN254 scalar field, built on [ModularArithmetic](../ModularArithmetic/README.md). Its API is internal to the module.

## Poseidon

[`Poseidon`](Sources/Poseidon/Poseidon.swift) is circom's x⁵ Poseidon over BN254, as light-poseidon v0.4.0 implements it:

- One to twelve inputs; the state is a zero domain tag followed by the inputs, a width t of 2 to 13. Other input counts throw `unsupportedInputCount`.
- 8 full rounds around 56 to 66 partial rounds, depending on t. The hash is the first element of the final state.
- Inputs are canonical field elements: 32 big-endian bytes below the modulus r, decoded with `FieldElement(bigEndianBytes:)`, which rejects other lengths and values at or above r.

## Parameters

- The round constants and MDS matrices are generated in Swift with the Grain LFSR method of hadeshash's [`generate_parameters_grain.sage`](https://extgit.isec.tugraz.at/krypto/hadeshash); no tables are copied.
- The hadeshash authors have deprecated that script. It is used because Solana Rings fixes circom's BN254 x⁵ parameters, and light-poseidon generated its tables with it.
- Each width's parameters are built on its first hash and kept for the rest of the process.
- Tests check the generated constants and matrices against the SHA-256 digests in zolana's Poseidon parity fixture, and hashes against all of its vectors.

## Side channels

The rounds depend only on the number of inputs. Field arithmetic follows ModularArithmetic's [side-channel note](../ModularArithmetic/README.md#side-channels).

## Sources

| Source | Version | Used for |
| --- | --- | --- |
| [Solana Rings](https://www.helius.dev/docs/privacy) by Helius, specified in zolana's [`spec.md`](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/docs/spec.md) | v0.4.0-alpha | The private-balance protocol this module implements |
| zolana's TypeScript [hasher](https://github.com/helius-labs/zolana/tree/v0.4.0-alpha/sdk-libs/ts/src/hasher) | v0.4.0-alpha | Reference for the hash the protocol uses; read, never run |
| zolana's [Poseidon parity fixture](https://github.com/helius-labs/zolana/blob/v0.4.0-alpha/sdk-libs/ts/vectors/poseidon-parity-v1.json) (Apache-2.0) | v0.4.0-alpha | Test digests and vectors, copied unchanged |
| [light-poseidon](https://github.com/Lightprotocol/light-poseidon/tree/v0.4.0) | 0.4.0 | Round structure and partial-round counts |
| hadeshash's [`generate_parameters_grain.sage`](https://extgit.isec.tugraz.at/krypto/hadeshash) | — | Grain LFSR method for the constants and matrices |
| [Poseidon: A New Hash Function for Zero-Knowledge Proof Systems](https://eprint.iacr.org/2019/458) | USENIX Security 2021 | The hash design |

Solana Rings is in beta, and its releases can change parameters, vectors, and hashing rules; v0.4.0-alpha stopped earlier clients from working. Check this module against every new zolana or light-poseidon release before updating these versions.
