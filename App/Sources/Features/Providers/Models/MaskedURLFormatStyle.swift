import Foundation

/// Formats a custom RPC's URL with its host in full and each path part and query value masked, so most of a key in
/// the URL stays hidden.
nonisolated struct MaskedURLFormatStyle: FormatStyle {
    /// Whether the output is for VoiceOver, which hears that each masked part's rest is hidden instead of each dot.
    var isSpoken = false

    /// Formats the URL with most of its path and query hidden.
    /// - Parameter url: The custom RPC's URL.
    /// - Returns: The URL as people see or hear it.
    func format(_ url: URL) -> String {
        let part = MaskedFormatStyle(isSpoken: isSpoken)
        var text = "\(url.scheme ?? "https")://\(url.host() ?? "")" + (url.port.map { ":\($0)" } ?? "")
        let path = url.pathComponents.filter { $0 != "/" }.map { $0.formatted(part) }
        if !path.isEmpty { text += "/" + path.joined(separator: "/") }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if !query.isEmpty {
            // A query item without a value, such as `?key`, holds the key in its name.
            let items = query.map { item in
                item.value.map { "\(item.name)=\($0.formatted(part))" } ?? item.name.formatted(part)
            }
            text += "?" + items.joined(separator: "&")
        }
        return text
    }
}

nonisolated extension FormatStyle where Self == MaskedURLFormatStyle {
    /// A custom RPC's URL with most of its path and query masked.
    static var maskedURL: Self { Self() }

    /// A masked custom RPC URL for VoiceOver, which hears that each masked part's rest is hidden.
    static var spokenMaskedURL: Self { Self(isSpoken: true) }
}
