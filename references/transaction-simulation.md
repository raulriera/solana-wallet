# Transaction simulation

- Current scope: RPC simulation returns execution errors, logs, and diagnostics without broadcasting a transaction.
- AI explanations aren't implemented and have no approved API. They are optional: when disabled, make no inference requests; unavailability, refusals, or failures must leave the simulation result usable.
- Keep model selection and fallback inside the framework: PCC first when available, then on-device; retain a basic explanation when AI is unavailable and preserve the original result.
- The initial value experiment requires real PCC inference with on-device fallback disabled. Local-model output and test doubles don't validate the cloud experience.

## Apple Intelligence research

- `PrivateCloudComputeLanguageModel` is present in the installed iOS 27.1 SDK. Foundation Models provides remote inference without an API key or app-owned backend.
- PCC has a 32K-token context and requires connectivity. The on-device `SystemLanguageModel` has a 4K-token context, works offline, and has unlimited usage. Both depend on Apple Intelligence availability.
- No cloud API cost requires App Store Small Business Program membership, fewer than two million first-time downloads for any app, and Apple's PCC entitlement. Users have daily quotas; iCloud+ increases access. The reviewed documentation gives no fixed daily request count.
- The user's iCloud+ allowance doesn't grant an app PCC access. Apple requires the entitlement and documents testing through TestFlight or ad hoc distribution; on-device inference and tests with injected models can proceed without PCC access.
- Check model availability and quota separately. A quota failure requires a reset or increased allowance, not immediate retries.

Sources: [Remote inference and quotas](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute.md), [eligibility](https://developer.apple.com/private-cloud-compute/).

## Explanation research

- Known errors can be resolved using program identity and code. Custom errors are program-specific; there is no complete universal catalogue. Definitions must match the program version.
- A simple candidate: Swift resolves known meanings and formats amounts, then supplies the matching definition, relevant logs, and transaction intent to the model. Unknown meanings remain unknown.
- Foundation Models accepts reference context directly; a `Tool` can retrieve definitions if needed later. `@Generable` enforces output structure, not factual correctness.
- Treat logs as untrusted data. Explanations must preserve the simulation outcome and uncertainty; a successful simulation does not guarantee a future transaction succeeds.
- Review real simulation outputs with the user: compare the basic explanation with actual PCC output using success, failure, and unknown-error examples. Iterate on supplied context, prompts, and output shape before expanding the framework.
- Judge whether AI adds accurate, understandable, useful information. Passing unit tests doesn't establish explanation quality; keep model-quality evaluation separate.

Sources: [Program-specific errors](https://www.anchor-lang.com/docs/features/errors), [reference lookup tools](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling.md), [typed generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation.md).

## Prompt evaluation

No explanation prompt is approved. Success explanations must not link signature verification to future confirmation. Facts and amounts require manual preparation; automatic interpretation is not implemented. Follow Apple's [evaluation guidance](https://developer.apple.com/documentation/foundationmodels/evaluating-prompts-to-measure-performance-and-improve-model-responses.md).
