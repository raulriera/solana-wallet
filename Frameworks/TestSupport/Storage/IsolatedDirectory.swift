import Foundation

final class IsolatedDirectory: Sendable {
    let url = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
