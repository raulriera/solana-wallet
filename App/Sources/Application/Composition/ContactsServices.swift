import Foundation
import Storage

/// The recent payments that every window's Contacts shares.
struct ContactsServices {
    /// Each wallet's recent payments on each network, keyed by ``ContactsModel/recentsKey(wallet:network:)``.
    let recents: PersistentValue<[String: [RecentPayment]]>
}

extension ContactsServices {
    /// Connects Contacts to the storage that keeps its recent payments, without reading it.
    /// - Parameter storage: The storage that keeps every wallet's recent payments.
    init(storage: any ValueStoring<[String: [RecentPayment]]>) {
        self.init(recents: PersistentValue(storage: storage, empty: [:]))
    }

    /// Connects Contacts to its recent payments' file in a directory, without reading it.
    /// - Parameter directory: The directory that keeps the Contacts files.
    init(directory: URL) {
        self.init(storage: FileItem(url: directory.appending(path: "recents.json"),
                                    coding: .json([String: [RecentPayment]].self)))
    }
}
