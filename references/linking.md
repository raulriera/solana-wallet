# Framework linking

- The app uses `MERGED_BINARY_TYPE = automatic` from `Configuration/App.xcconfig` in both configurations. Shared language/platform settings remain in the project-level configuration.
- Framework modules: RPC, Portfolio, Wallet, Vault, Transactions, and Encoding. Xcode links them dynamically in Debug and merges their implementations into the app executable in Release. Transaction workflow coordination compiles directly into the app under the approved [architecture](architecture.md).
- Frameworks participating in automatic merging must be direct app dependencies and appear in its Link Binary with Libraries phase. Keep the merging setting on the app, not on every framework.
- Encoding participates in merging too, so the Release executable contains one codec implementation. Xcode may retain small framework bundle hooks for resource lookup; these aren't runtime dependencies of the Release executable.
- Verification: Debug and Release builds and simulator launches; inspect executable load commands and shared-code symbols. Launch-time improvements require profiling and aren't inferred from build duration.

Source: [Apple mergeable libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries.md).
