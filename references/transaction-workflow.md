# Transaction workflow

`TransactionCoordinator` is the one path for every instruction composition, transfers included: `simulate`, explicit approval, `submit`, then `confirm`.

- Views never assemble wire bytes, blockhashes, signature slots, or submission requests.
- Imported transactions keep their original message and cosignatures and are never rebuilt.
- Each review allows one signing attempt, except a send with preliminary transactions: its one approval covers the number of transactions that the review showed, and each is simulated before it is signed. Before wallet access, submission checks the message, signatures, fee, and lifetime again; a changed or expired message needs a new simulation and approval. Recovery stays local to signing.
- Explicit resource and fee configuration is never changed silently.

## Submission and observation

- Each transaction is sent once. `standard` and `premium` send through Helius Sender only, mainnet only, with no fallback. Changing strategy needs a new coordinator and review.
- Sender tips are ordinary instructions added before estimation and review, ahead of the caller's instructions.
- Preflight runs at `finalized` with zero node retries. Nothing rebuilds, signs again, or resubmits, except a send with preliminary transactions, which sends a dropped transaction again at most 2 times. An error after signing keeps the transaction's receipt.
- Confirmation has no timeout and no unknown result: a transaction is dropped only after a finalized block height passes its blockhash's last valid height.
