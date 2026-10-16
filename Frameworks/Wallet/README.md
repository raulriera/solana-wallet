# Wallet

Local recovery phrase generation, Solana account derivation, Ed25519 signing, and Solana Rings private-balance keys. Uses Apple cryptography and secure randomness, with a bundled English BIP-39 word list. [ModularArithmetic](../ModularArithmetic/README.md) does the P-256 scalar sums of key derivation.

## Example Usage

Inject [`WalletProviding`](Sources/Service/WalletProviding.swift) for phrase generation and account derivation, [`MessageSigning`](Sources/Signing/MessageSigning.swift) for signing, or [`PrivateBalanceKeyDeriving`](Sources/PrivateBalance/PrivateBalanceKeyDeriving.swift) for private-balance keys. `Wallet` implements all three protocols.

Given recovery text and its original BIP-39 passphrase:

```swift
import Wallet

let service: any WalletProviding = Wallet()
let phrase = try RecoveryPhrase(recoveryText)
let accounts = try await service.accounts(
    for: phrase,
    passphrase: passphrase,
    paths: [.solana]
)
```

- `recoveryPhrase(wordCount:)` generates 12, 15, 18, 21, or 24 words. `RecoveryPhrase` validates imported words and their checksum.
- `accounts(for:passphrase:paths:)` derives addresses using one temporary seed, preserving the requested order and duplicates.
- `DerivationPath.solana` is `m/44'/501'/0'/0'`. Other hardened SLIP-0010 paths can be parsed with `DerivationPath(_:)`.
- `signature(for:using:expectedAddress:passphrase:path:)` signs exact message bytes after checking that the recovered account matches the expected address. It returns a 64-byte signature or throws; it does not interpret the message, but refuses Solana Rings key derivation inputs with `SigningError.reservedMessage`: messages that start with `TSPP/derive/`, bare or as the payload of a Solana off-chain message version 0.

## Private-balance keys

`privateBalanceKeys(using:expectedAddress:passphrase:path:)` derives an account's keys for the Solana Rings seed-phrase scenario. It's the only Wallet API that returns secret keys.

- Only accounts at `m/44'/501'/i'/0'` have keys; other paths throw `PrivateBalanceError.unsupportedPath`. `DerivationPath.hasPrivateBalanceKeys` checks a path before recovery is read. The account index i selects the key paths, under coin type 1392955331.
- One temporary seed derives the account's Ed25519 key first; a malformed address or a different account throws `PrivateBalanceError.accountMismatch` before the private-balance keys are derived.
- `nullifierSecret` is the SLIP-0010 Ed25519 node key at `m/44'/1392955331'/i'/1'/0'` without its first byte, a 31-byte CryptoKit `SymmetricKey`.
- `viewingKey` is the SLIP-0010 nist256p1 node key at `m/44'/1392955331'/i'/2'/0'`, a CryptoKit `P256.KeyAgreement.PrivateKey`.
- `PrivateBalanceKeys` descriptions and reflection omit both secrets. The caller owns their protection and lifetime.

## Recovery and integration

Recovery requires the original phrase, passphrase, and account path. Public addresses are independent of the selected Solana network. Derivation and signing run concurrently outside the caller's actor and support cancellation.

The service retains no secret state and performs no networking or persistence. Seed and key byte buffers are zeroed after use on a best-effort basis; ModularArithmetic's scalar values can't be erased. Phrase and recovery descriptions omit secrets; explicit property access exposes them, and Swift does not guarantee memory erasure.

Use [Vault](../Vault/README.md) for protected recovery storage. The caller owns backup verification, account discovery, authentication, and approval before signing.
