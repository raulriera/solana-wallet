import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let themePack = UTType(exportedAs: "com.raulriera.xtheme", conformingTo: .package)
}

/// A fully prepared package; the system exporter copies it without serializing in a view.
nonisolated struct ThemeExport: Transferable, Sendable, Equatable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .themePack) { value in
            SentTransferredFile(value.url)
        }
        .suggestedFileName { $0.url.lastPathComponent }
    }
}
