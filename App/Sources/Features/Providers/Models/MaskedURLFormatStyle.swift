import Foundation

/// Formats a custom RPC's URL with its host in full and each path part and query value masked.
nonisolated struct MaskedURLFormatStyle: FormatStyle {
    /// Whether the output says each masked part's rest is hidden instead of showing dots.
    var isSpoken = false

    func format(_ url: URL) -> String {
        let part = MaskedFormatStyle(isSpoken: isSpoken)
        var text = "\(url.scheme ?? "https")://\(url.host() ?? "")" + (url.port.map { ":\($0)" } ?? "")
        let path = url.pathComponents.filter { $0 != "/" }.map { $0.formatted(part) }
        if !path.isEmpty { text += "/" + path.joined(separator: "/") }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if !query.isEmpty {
            let items = query.map { item in
                item.value.map { "\(item.name)=\($0.formatted(part))" } ?? item.name.formatted(part)
            }
            text += "?" + items.joined(separator: "&")
        }
        return text
    }
}

nonisolated extension FormatStyle where Self == MaskedURLFormatStyle {
    static var maskedURL: Self { Self() }

    static var spokenMaskedURL: Self { Self(isSpoken: true) }
}
