import Foundation

/// Samples each logo once and shares its color with every window.
///
/// Only logos bundled with the app or served over HTTPS load. A logo without a usable color is remembered too,
/// so it doesn't load again; a failed or cancelled load is tried again on the next request.
actor ArtworkColors: ArtworkColorProviding {
    /// Loads a logo request and returns its data and response.
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let fetch: Fetch
    private var colors: [URL: ArtworkColor?] = [:]

    /// Creates a sampler that loads logos with the given request handler.
    /// - Parameter fetch: Loads a logo request; the default uses the shared URL session.
    init(fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }) {
        self.fetch = fetch
    }

    /// Returns the logo's remembered color, or loads and samples it.
    /// - Parameter url: The app's bundled copy, or the logo's HTTPS location on the provider's CDN.
    /// - Returns: The logo's representative color, or `nil` when the logo can't load or has no color.
    func color(for url: URL) async -> ArtworkColor? {
        guard url.isFileURL || url.scheme?.lowercased() == "https" else { return nil }
        if let color = colors[url] { return color }
        // Logos rarely change, so any cached copy is used before the provider is asked again.
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        guard let (data, response) = try? await fetch(request) else { return nil }
        // A bundled file has no HTTP status; the provider's copy must arrive successfully.
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) { return nil }
        let color = ArtworkSampler.color(from: data)
        colors.updateValue(color, forKey: url)
        return color
    }
}
