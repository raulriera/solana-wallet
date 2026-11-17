# Contributing

Fixes and improvements are welcome. For a new feature, open an issue first so we can agree on the design before you write code.

The full rules are in [AGENTS.md](AGENTS.md) and [references/](references/). This file gives the main points.

## Scope

- Keep the app decentralized: no app backend, proxy, or analytics. The app connects directly to Solana RPC providers.
- Use Swift and Apple frameworks only. Do not add third-party dependencies unless strictly necessary.

## Providers

- All Solana RPC, DAS, and price requests go through the shared protocols in the [RPC framework](Frameworks/RPC). Providers are implementations of these protocols and must be interchangeable.
- Never put API keys in source code or the app bundle. Users enter keys in the app.

## Security

- Do not weaken the [security settings](README.md#security) or the app's entitlements.
- Recovery material stays on the device: no iCloud sync and no backups. See [references/wallet.md](references/wallet.md).

## Style

- Swift 6 and SwiftUI. Use the latest APIs, with no deprecated or older-iOS code paths.
- Put each view in its own file. Do not return views from computed properties or helper functions.
- Match the existing names, folders, and code shapes.
- Write DocC comments for production code only. Add no other comments.

## Pull requests

- Keep each pull request to one concern and at most 8 files, not counting Markdown files. If longer, use stacks.
- Use [Conventional Commits](https://www.conventionalcommits.org) for commit messages, and name branches `<type>/<topic>`, such as `fix/token-logo`.
- Rebase onto `main`. Do not add merge commits.
- Fill in the [pull request template](.github/pull_request_template.md).

## Tests

- The Unit test plan must pass. It never uses the network.
- Write new tests following [references/testing.md](references/testing.md).
- Never reimplement a server's logic in a test RPC. Use a mock RPC when the code under test only needs one injected.
