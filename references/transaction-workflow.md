# Transaction workflow

`TransactionCoordinator` is the one path for every instruction composition, transfers included: `simulate`, explicit approval, `submit`, then `confirm`.

- Program helpers produce instructions. Views never assemble wire bytes, blockhashes, signature slots, or submission requests.
- Imported transactions keep their original message and cosignatures and are never rebuilt. `sign(simulation)` returns signed bytes without sending them.
- Each review allows one signing attempt. Before wallet access, submission checks the message, signatures, network, fee, and lifetime again; a changed or expired message needs a new simulation and approval. Recovery stays local to signing.
- Explicit resource and fee configuration is never changed silently.

## Submission and observation

- Each transaction goes through one RPC, once. `none` sends through the selected provider. `standard` and `premium` send through Helius Sender only, mainnet only, with no fallback. Changing strategy needs a new coordinator and review.
- Sender tips are ordinary instructions added before estimation and review, ahead of the caller's instructions so a payment can stay last. Standard tips 5,000 lamports; premium tips 1,000,000 lamports with at least 5,000 priority-fee lamports. These are minimum bids, not landing guarantees.
- Preflight runs at `finalized` with zero node retries. Nothing rebuilds, signs again, or resubmits. An error after signing keeps its receipt in `DeliveryError`, so the transaction can be watched again.
- `confirm` reports succeeded, failed (the fee is still paid), or dropped once a finalized block height passes the blockhash's last valid height. There is no timeout and no unknown result.

Sources: [Sender](https://www.helius.dev/docs/sending-transactions/sender-swqos-only.md), [submission](https://solana.com/docs/rpc/http/sendtransaction.md), [signature status](https://solana.com/docs/rpc/http/getsignaturestatuses.md).
