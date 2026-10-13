import Testing

extension Tag {
    /// Marks tests that send requests to real RPC, DAS, or price providers.
    ///
    /// The Unit test plan skips these tests; the Integration test plan runs only them.
    @Tag static var network: Self
}
