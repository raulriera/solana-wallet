# RPC scope

Build for the agreed Simplified and Advanced wallet experiences. A test or hypothetical future use alone doesn't justify an RPC method.

Connect directly to interchangeable Solana RPC/DAS providers; no app-owned backend or proxy. Helius is the current implementation. Keep provider-specific endpoints, authentication, and extensions inside RPC; consumers depend on provider-neutral protocols. App workflow coordination follows [architecture](architecture.md).

| Feature | RPC need |
| --- | --- |
| Create/import seed phrases; view/copy address | None. Keep these local. |
| View portfolio | DAS through `GetAssetsByOwner`, including native SOL, asset metadata, and available prices. |
| V1 transactions | Blockhash and expiry (including `IsBlockhashValid` for supplied transactions), fee estimates, simulation, submission, and signature status. |
| AI-enhanced transaction simulation | Reuse simulation results, logs, and errors for human-readable explanations in a separate framework after RPC; see [simulation explanations](transaction-simulation.md). |

- Confidential transfers remain conditional; agree on feasibility and the concrete flow before adding support.
- Raw account, rent-exemption, and node-version queries are outside the current scope. Add them only when an agreed feature needs them.
- RPC completion means the agreed flows have the communication they need. Human-readable simulation explanations remain a separate milestone; AI exploration is parked. UI remains last.
