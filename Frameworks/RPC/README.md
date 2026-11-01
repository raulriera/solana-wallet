# RPC

Typed Solana RPC, DAS asset queries, prices, exchange rates, and account and signature subscriptions. Clients connect directly to providers.

## Usage

```swift
import RPC

let client: any RPC = Solana(network: .devnet)
let response = try await client.send(GetLatestBlockhash())
let blockhash = response.value.blockhash
```

The module includes `Solana`, `HeliusRPC`, and `Sender` for RPC and submission, `Zolana` for Solana Rings indexer reads and encrypted proofs, `Jupiter` for prices, and `EuropeanCentralBank` and `Coinbase` for exchange rates.

## Use a custom RPC URL

`Solana(endpoint:network:)` accepts an HTTPS URL with a host and returns `nil` otherwise. The server must serve standard JSON-RPC requests at that URL, and `accountSubscribe`, `signatureSubscribe`, and `rootSubscribe` over WSS at the same URL.

```swift
let client = Solana(endpoint: URL(string: "https://rpc.example.com")!, network: .mainnet)
```

## Add a provider

A provider is a type in this module that conforms to [`RPC`](Sources/Client/RPC.swift) and sends each `RPCRequest` to its endpoint. Wrap a `Solana` client for an endpoint that speaks standard Solana RPC, as `HeliusRPC` does. Add the optional capabilities that the provider serves:

| Protocol | Capability |
| --- | --- |
| [`AccountChangeProviding`](Sources/Subscriptions/AccountChangeProviding.swift) | Finalized account change subscriptions |
| [`SignatureEventProviding`](Sources/Subscriptions/SignatureEventProviding.swift) | Signature and root subscriptions |
| [`LogoProviding`](Sources/Assets/LogoProviding.swift) | HTTPS token logos hosted by the provider |
| [`PrivateNoteProviding`](Sources/PrivateNotes/PrivateNoteProviding.swift) | Solana Rings indexer reads |
| [`ProofProviding`](Sources/Proofs/ProofProviding.swift) | Solana Rings transfer proofs |
| [`PriceProviding`](Sources/Pricing/PriceProviding.swift) | Token prices keyed by mint |
| [`ExchangeRateProviding`](Sources/Pricing/ExchangeRateProviding.swift) | Currency exchange rates |

Throw `RPCError` for failures, and send each request once: callers handle rate limits and retries.
