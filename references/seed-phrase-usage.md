# Seed phrase handling

Research checked September 27, 2026. Approved storage and recovery requirements are in [wallet.md](wallet.md); UI remains a later milestone.

## Incident lessons

- **Slope, 2022:** secret key material reached application monitoring. Excluding secrets at collection matters; later redaction cannot undo exposure. The exact route from exposure to theft remained unresolved. [Solana](https://solana.com/news/8-2-2022-application-wallet-incident), [Slope investigation](https://slope-finance.medium.com/slope-wallet-sentry-vulnerability-digital-forensics-and-incident-response-report-d7a5904e5a39).
- **Trust Wallet browser extension, 2022–23:** a 32-bit random seed made recovery phrases enumerable, including accounts holding SOL. Phrase length cannot compensate for weak entropy. [Ledger Donjon investigation](https://www.ledger.com/blog/funds-of-every-wallet-created-with-the-trust-wallet-browser-extension-could-have-been-stolen).
- **Solana web3.js, 2024:** compromised releases 1.95.6/1.95.7 exfiltrated private keys from applications handling them. Keep dependencies around secrets minimal and review updates; this was a package compromise, not a Solana protocol flaw. [Maintainer advisory](https://github.com/solana-foundation/solana-web3.js/security/advisories/GHSA-jcxm-7wvp-g6p5).

## Practices

- Generate entropy with [`SecRandomCopyBytes`](https://developer.apple.com/documentation/security/secrandomcopybytes(_:_:_:).md); fail closed on failure. Our twelve-word default requires 128 random bits. Never derive phrases from user-chosen words, timestamps, or AI.
- Preserve standard words, checksums, Unicode normalization, passphrases, and derivation paths. Backups must retain any passphrase and account path needed for recovery. Verify published [BIP-39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki) and [SLIP-0010](https://github.com/satoshilabs/slips/blob/master/slip-0010.md) vectors; use only public fixtures.
- Keep phrases, passphrases, seeds, and private keys out of logs, analytics, crash payloads, support messages, Helius requests, and AI/PCC prompts. Masked wrapper descriptions do not protect explicitly accessed contents.
- Minimize secret copies and lifetime. Swift `String`/`Array`, `Sendable`, task cancellation, and framework boundaries do not guarantee memory erasure or isolation from other code in the process.
- Enforce [Keychain accessibility and item-level authentication](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id.md) under the approved device-only policy. Never use preferences, portfolio caches, source files, or xcconfig for wallet secrets. Biometric unlock does not replace recovery backups.
- Avoid automatic clipboard export. If copying is explicitly offered, use [`localOnly`](https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/localonly.md) and [`expirationDate`](https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/expirationdate.md); these limit propagation and lifetime, not all local exposure.
- After known phrase exposure, migrate to a wallet generated from fresh entropy. Changing the app PIN, reinstalling, or selecting another account under the same phrase does not revoke the leaked secret. [Solana recovery guidance](https://solana.com/news/8-2-2022-application-wallet-incident).

Wallet performs local derivation; Vault supplies separate device-only persistence. These practices and offline tests don't certify device authentication, signing, or future UI integrations.
