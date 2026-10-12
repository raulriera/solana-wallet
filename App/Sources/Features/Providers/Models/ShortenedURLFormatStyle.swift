import Foundation

/// Formats a custom RPC's URL with its host in full and each path part and query value shortened, so most of a key
/// in the URL stays hidden.
nonisolated struct ShortenedURLFormatStyle: FormatStyle {
    /// Formats the URL with most of its path and query hidden.
    /// - Parameter url: The custom RPC's URL.
    /// - Returns: The URL as people see it.
    func format(_ url: URL) -> String {
        var text = "\(url.scheme ?? "https")://\(url.host() ?? "")" + (url.port.map { ":\($0)" } ?? "")
        let path = url.pathComponents.filter { $0 != "/" }.map { $0.formatted(.shortened) }
        if !path.isEmpty { text += "/" + path.joined(separator: "/") }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if !query.isEmpty {
            // A query item without a value, such as `?key`, holds the key in its name.
            let items = query.map { item in
                item.value.map { "\(item.name)=\($0.formatted(.shortened))" } ?? item.name.formatted(.shortened)
            }
            text += "?" + items.joined(separator: "&")
        }
        return text
    }
}

nonisolated extension FormatStyle where Self == ShortenedURLFormatStyle {
    /// A custom RPC's URL with most of its path and query hidden.
    static var shortenedURL: Self { Self() }
}
