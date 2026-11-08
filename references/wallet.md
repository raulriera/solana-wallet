# Wallet

## Recovery

- New phrases have 12 English BIP-39 words; imports accept all five standard lengths. Addresses derive with the BIP-39 passphrase and hardened SLIP-0010 Ed25519 paths, `m/44'/501'/0'/0'` by default. Recovery needs the original passphrase and exact path, so account metadata stores the exact path.
- The Wallet framework stays local and cryptographic: no network, no persistence, no retained secrets. Signing neither authenticates nor interprets intent. It refuses Solana Rings key-derivation messages, which start with `TSPP/derive/`.
- Vault's `KeychainStore` keeps recovery in non-synchronizing Keychain items with `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and `userPresence`. No iCloud sync or backup.
- Access uses biometrics or the device passcode, interchangeably. A passcode is required; removing it deletes recovery.
- Onboarding and backup screens say that the recovery phrase, with any BIP-39 passphrase, is the only way to recover the wallet.
- Private-balance keys, notes, and redeem codes stay in the device-only Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) without authentication. Only deriving the keys reads recovery.

## Discovery

- Import checks indices 0–9 of `m/44'/501'/i'/0'` and `m/44'/501'/i'`: twenty addresses in one `GetMultipleAccounts` request, with no continuation.
- Keep only addresses with a positive SOL balance. By product decision, zero-SOL and missing accounts are ignored, even when they hold tokens or history. No token, history, or DAS lookups.
- Errors fail the scan; never return an empty result for them. A successful empty scan selects `m/44'/501'/0'/0'`.

## Saved data

- Saved data lives in `URL.persistentDirectory`, data the app can create again in `URL.ephemeralDirectory`. Application Support is excluded from backups; no app data moves to another device.
- On launch with no saved wallet, delete every recovery item in the app's Keychain namespace. Never touch saved wallets; a loading error is a failure, not an empty wallet.

## Verification

- Use published vectors and public test phrases only. Verify signatures cryptographically; CryptoKit may randomize them.
- Use the [biometric-tests skill](../.claude/skills/biometric-tests/SKILL.md) for Keychain checks. Simulator reads can skip the authentication prompt, so authentication needs a physical device.

Sources: [BIP-39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki), [SLIP-0010](https://github.com/satoshilabs/slips/blob/master/slip-0010.md), [user presence](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/userpresence.md).
