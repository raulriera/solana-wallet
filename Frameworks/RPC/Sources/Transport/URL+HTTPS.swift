import Foundation

extension URL {
    /// The absolute URL, or `nil` unless it uses HTTPS and has a host.
    var httpsEndpoint: URL? {
        let url = absoluteURL
        guard url.scheme?.lowercased() == "https", url.host()?.isEmpty == false else { return nil }
        return url
    }
}
