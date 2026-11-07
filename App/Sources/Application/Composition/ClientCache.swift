/// Keeps the client for the most recent endpoint and replaces it when the endpoint changes.
actor ClientCache<Endpoint: Equatable & Sendable, Client: Sendable> {
    private let make: @Sendable (Endpoint) throws -> Client
    private var current: (endpoint: Endpoint, client: Client)?

    /// Creates an empty cache.
    ///
    /// - Parameter make: A function that creates the client for an endpoint, or throws when it can't be used.
    init(make: @escaping @Sendable (Endpoint) throws -> Client) {
        self.make = make
    }

    /// Returns the kept client for this endpoint, or creates one for a new endpoint.
    ///
    /// - Parameter endpoint: The endpoint for the request.
    /// - Returns: A client that sends requests to this endpoint.
    /// - Throws: The error of the function that creates the client.
    func client(for endpoint: Endpoint) throws -> Client {
        if let current, current.endpoint == endpoint { return current.client }
        let client = try make(endpoint)
        current = (endpoint, client)
        return client
    }
}
