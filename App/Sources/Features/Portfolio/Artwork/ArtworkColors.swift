import Foundation

/// Samples each logo once and remembers its color.
actor ArtworkColors: ArtworkColorProviding {
    /// A function that loads a request and returns its data and response.
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let fetch: Fetch
    private var colors: [URL: ArtworkColor?] = [:]

    /// Creates a sampler that loads logos with the given function.
    ///
    /// - Parameter fetch: The function that loads a logo request.
    init(fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }) {
        self.fetch = fetch
    }

    func color(for url: URL) async -> ArtworkColor? {
        guard url.isFileURL || url.scheme?.lowercased() == "https" else { return nil }
        if let color = colors[url] { return color }
        guard let (data, response) = try? await fetch(URLRequest(url: url)) else { return nil }
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) { return nil }
        let color = ArtworkSampler.color(from: data)
        colors.updateValue(color, forKey: url)
        return color
    }
}
