import Foundation
import Storage

/// The saved contacts and recent payments that every window's Contacts shares.
struct ContactsServices {
    /// Saved contacts and favorites, shared by every wallet and network.
    let addressBook: any ValueStoring<AddressBook>
    /// Each wallet's recent payments on each network, keyed by ``ContactsModel/recentsKey(wallet:network:)``.
    let recents: any ValueStoring<[String: [RecentPayment]]>
    /// Advances after each change is saved or fails to save, so every window reads what's saved.
    let revision = Revision()
}

extension ContactsServices {
    /// Connects Contacts to its files in a directory.
    /// - Parameter directory: The directory that keeps the Contacts files.
    init(directory: URL) {
        self.init(addressBook: FileItem(url: directory.appending(path: "contacts.json"),
                                        coding: .json(AddressBook.self)),
                  recents: FileItem(url: directory.appending(path: "recents.json"),
                                    coding: .json([String: [RecentPayment]].self)))
    }
}
