# Wallet

## Recovery

- Store each account's exact derivation path in its metadata.
- The Wallet framework stays local and cryptographic: no network, no persistence, no retained secrets. Signing neither authenticates nor interprets intent. It refuses Solana Rings key-derivation messages.
- Vault's `KeychainStore` keeps recovery in non-synchronizing Keychain items with `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and `userPresence`.
- Each recovery read authenticates the person on its own. The one exception is a send that needs several transactions: its reads share one authentication, which ends when the send ends or fails, or, when the app goes to the background, before it starts its next transaction.
- Onboarding and backup screens say that the recovery phrase, with any BIP-39 passphrase, is the only way to recover the wallet.
- Private-balance keys, notes, and redeem codes stay in the device-only Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) without authentication. Only deriving the keys reads recovery.

## Discovery

- Discover accounts with one SOL-only lookup for twenty addresses.
- Make no follow-up, token, history, or DAS lookups.
- Ignore zero-SOL and missing accounts, even when they hold tokens or history.
- Errors fail the scan; never return an empty result for them.

## Saved data

- No app data moves to another device.
- On launch with no saved wallet, delete every recovery item in the app's Keychain namespace.

## Verification

- Use published vectors and public test phrases only. Verify signatures cryptographically.
- Use the [biometric-tests skill](../.claude/skills/biometric-tests/SKILL.md) for Keychain checks. Check authentication on a physical device.
