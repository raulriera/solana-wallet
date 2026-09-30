# Wallet

Local recovery phrase generation, Solana account derivation, and Ed25519 signing. Uses Apple cryptography and secure randomness, with a bundled English BIP-39 word list.

## Example Usage

Inject [`WalletProviding`](Service/WalletProviding.swift) for phrase generation and account derivation, or [`MessageSigning`](Signing/MessageSigning.swift) for signing. `Wallet` implements both protocols.

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
- `address(for:passphrase:path:)` derives one address. `accounts(for:passphrase:paths:)` derives a batch using one temporary seed, preserving the requested order and duplicates.
- `DerivationPath.solana` is `m/44'/501'/0'/0'`. Other hardened SLIP-0010 paths can be parsed with `DerivationPath(_:)`.
- `signature(for:using:expectedAddress:passphrase:path:)` signs exact message bytes after checking that the recovered account matches the expected address. It returns a 64-byte signature or throws; it does not interpret the message.

## Recovery and integration

Recovery requires the original phrase, passphrase, and account path. Public addresses are independent of the selected Solana network. Derivation and signing run concurrently outside the caller's actor and support cancellation.

The service retains no secret state and performs no networking or persistence. Phrase and recovery descriptions omit secrets; explicit property access exposes them, and Swift does not guarantee memory erasure.

Use [Vault](../Vault/README.md) for protected recovery storage. The caller owns backup verification, account discovery, authentication, and approval before signing.
