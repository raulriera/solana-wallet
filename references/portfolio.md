# Portfolio

- Cap each account's token list at 50 tokens, native SOL included. Native SOL can't be removed.
- Accept only fungible SPL Token and Token-2022 mints; NFTs are deferred.
- Keep balances exact, and native SOL distinct from Wrapped SOL. A missing quote is an unknown value and a missing change is an unknown change, never zero. Devnet shows amounts without value.
- When another address controls a token's associated account, show no balance, value, or price for it.
- Read balances again after finalized changes to the wallet or its token accounts; never poll.
- Keep data on screen after errors and while reconnecting.
