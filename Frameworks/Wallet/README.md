# Wallet

Recovery phrase generation, Solana account derivation, Ed25519 signing, and Solana Rings private-balance keys, with Apple cryptography only.

## Usage

```swift
import Wallet

let wallet = Wallet()
let phrase = try RecoveryPhrase(recoveryText)
let accounts = try await wallet.accounts(for: phrase, passphrase: passphrase, paths: [.solana])
```

`Wallet` implements `WalletProviding` for phrases and accounts, `MessageSigning` for signatures, and `PrivateBalanceKeyDeriving` for private-balance keys. Store phrases with [Vault](../Vault/README.md).
