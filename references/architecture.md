# Architecture

- App composition creates shared services and `@MainActor @Observable` stores once, for the app's lifetime; views read stores from the environment. Scenes create the coordinators and workflow models they use. Views present state and capture approval.
- Features derive what they show from stores instead of calling each other. Every store that saves data joins `AppReset`'s `Erasable` list.
- A window keeps only navigation. Tabs own their workflow models as `@State` and pass the window's account and network into each call instead of storing them.
- Keep signing independent of submission.
- Bind review and signing to the exact message, account, and network. Authentication grants wallet access; approval is separate. Simulation success isn't proof of safety.
- Program helpers produce `Instruction` values. A composition stays atomic: nothing splits automatically. Durable nonces aren't supported.
- Keep `MERGED_BINARY_TYPE = automatic` on the app only, and link every framework directly from the app.
