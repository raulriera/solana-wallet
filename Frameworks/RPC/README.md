# RPC

Typed Solana RPC, DAS asset queries, market prices, and confirmed account subscriptions. Clients connect directly to providers and encapsulate request encoding, transport, and response decoding.

## Example Usage

Inject [`RPC`](Sources/Client/RPC.swift) and send an `RPCRequest`; its associated `Response` defines the result type.

```swift
import RPC

let client: any RPC = Solana(network: .devnet)
let response = try await client.send(GetLatestBlockhash())
let blockhash = response.value.blockhash
```

| Provider | Capabilities |
| --- | --- |
| `Solana(network:)` | Public mainnet or devnet RPC and confirmed account subscriptions. No DAS. |
| `HeliusRPC(apiKey:network:)` | Mainnet or devnet RPC, DAS, and confirmed account subscriptions. |
| `Sender(tier:)` | Optional mainnet transaction submission with `standard` or `premium` routing. Preparation and confirmation use ordinary RPC. |
| `Jupiter(apiKey:)` | Mainnet prices through `PriceProviding`; independent of RPC and DAS. |

Typed requests cover account and rent reads, blockhash lifetime, epochs, fees, simulation, submission, signature status, and fungible-asset queries. See [supported request scope](../../references/rpc-scope.md).

## Prices and subscriptions

[`PriceProviding`](Sources/Pricing/PriceProviding.swift) returns quotes keyed by mint. Missing entries mean unavailable prices, not zero. A quote may include its 24-hour change as a fraction; a missing change is unknown, not zero. Providers own deduplication, batching, and pacing. Reuse a provider instance to share its request budget; refresh scheduling belongs to the caller.

[`AccountChangeProviding`](Sources/Subscriptions/AccountChangeProviding.swift) observes confirmed SOL, SPL Token, and Token-2022 account changes. `changedSlots(for:)` returns after subscriptions are acknowledged and emits increasing change slots. These signal a need to reconcile balances; they are not balance updates. Cancel the consuming task to close its connection.

## Errors and submission

Requests are single-attempt. Ordinary RPC and DAS calls are not throttled; price batches are paced within provider limits. HTTP rate limits surface as `RPCError.http(statusCode:retryAfter:)`. Failed price batches throw without partial results. Subscription failures end the stream without automatic reconnection.

The caller owns transaction construction, review, signing, routing, and confirmation. `submissionRequirements` exposes a submission service's tip and minimum priority fee for inclusion before signing. Sending bytes does not establish confirmation.

Method availability depends on the provider. Helius priority-fee estimates are verified only for account-based mainnet requests; devnet and transaction-based V1 estimates remain unverified.
