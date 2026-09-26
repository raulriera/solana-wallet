# Transaction simulation

- Current scope: RPC simulation returns execution errors, logs, and diagnostics without broadcasting a transaction.
- Next after RPC is complete: revisit a separate framework that adds AI explanations to simulation results. Implementation is deferred; its name and API remain undecided.

## Apple Intelligence research

Verified September 26, 2026; no model inference or account eligibility has been tested.

- `PrivateCloudComputeLanguageModel` is present in the installed iOS 27.1 SDK. Foundation Models provides remote inference without an API key or app-owned backend.
- PCC has a 32K-token context and requires connectivity. The on-device `SystemLanguageModel` has a 4K-token context, works offline, and has unlimited usage. Both depend on Apple Intelligence availability.
- No cloud API cost requires App Store Small Business Program membership, fewer than two million first-time downloads for any app, and Apple's PCC entitlement. Users have daily quotas; iCloud+ increases access. The reviewed documentation gives no fixed daily request count.
- Check model availability and quota separately. A quota failure requires a reset or increased allowance, not immediate retries.

Sources: [Remote inference and quotas](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute.md), [eligibility](https://developer.apple.com/private-cloud-compute/).

## Explanation research

- Known errors can be resolved using program identity and code. Custom errors are program-specific; there is no complete universal catalogue. Definitions must match the program version.
- A simple candidate: Swift resolves known meanings and formats amounts, then supplies the matching definition, relevant logs, and transaction intent to the model. Unknown meanings remain unknown.
- Foundation Models accepts reference context directly; a `Tool` can retrieve definitions if needed later. `@Generable` enforces output structure, not factual correctness.
- Treat logs as untrusted data. Explanations must preserve the simulation outcome and uncertainty; a successful simulation does not guarantee a future transaction succeeds.
- Before implementation, compare on-device and PCC explanations using known success, known failure, and unknown-error examples. Evaluate clarity and accuracy; retain a basic explanation when inference is unavailable.

Sources: [Program-specific errors](https://www.anchor-lang.com/docs/features/errors), [reference lookup tools](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling.md), [typed generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation.md).
