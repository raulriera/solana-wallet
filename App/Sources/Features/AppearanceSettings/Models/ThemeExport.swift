import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let themePack = UTType(exportedAs: "com.raulriera.xtheme", conformingTo: .package)
}

/// A staged theme package for the system exporter.
nonisolated struct ThemeExport: Transferable, Sendable, Equatable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .themePack) { value in
            SentTransferredFile(value.url)
        }
        .suggestedFileName(\.url.lastPathComponent)
    }
}
