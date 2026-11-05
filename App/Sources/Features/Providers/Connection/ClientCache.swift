/// Keeps the client for the most recent endpoint and replaces it when the endpoint changes.
actor ClientCache<Endpoint: Equatable & Sendable, Client: Sendable> {
    private let make: @Sendable (Endpoint) -> Client?
    private var current: (endpoint: Endpoint, client: Client)?

    /// Creates an empty cache.
    ///
    /// - Parameter make: A function that creates the client for an endpoint.
    init(make: @escaping @Sendable (Endpoint) -> Client?) {
        self.make = make
    }

    /// Returns the kept client for this endpoint, or creates one for a new endpoint.
    ///
    /// - Parameter endpoint: The endpoint for the request.
    /// - Returns: A client that sends requests to this endpoint.
    /// - Throws: ``ProviderClientError/unusableEndpoint`` for a saved endpoint that can't be used.
    func client(for endpoint: Endpoint) throws -> Client {
        if let current, current.endpoint == endpoint { return current.client }
        guard let client = make(endpoint) else { throw ProviderClientError.unusableEndpoint }
        current = (endpoint, client)
        return client
    }
}
