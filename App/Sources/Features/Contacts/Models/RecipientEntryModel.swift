import Foundation
import Observation
import Transactions

/// Owns one recipient sheet: a pasted address and an optional name, for a new payment or a new contact.
@MainActor
@Observable
final class RecipientEntryModel: Identifiable {
    /// What confirming the sheet does.
    nonisolated enum Purpose: Hashable, Sendable {
        /// Pays the address; a name also saves it as a contact.
        case payment
        /// Saves the address as a contact under a name.
        case addContact

        /// The sheet's title.
        var title: LocalizedStringResource {
            switch self {
            case .payment: "New Payment"
            case .addContact: "Add Contact"
            }
        }

        /// The name of the confirm button, which VoiceOver reads.
        var confirmationTitle: LocalizedStringResource {
            switch self {
            case .payment: "Continue"
            case .addContact: "Save Contact"
            }
        }

        /// The name field's placeholder, which says whether a name is needed.
        var namePlaceholder: LocalizedStringResource {
            switch self {
            case .payment: "Name (Optional)"
            case .addContact: "Name"
            }
        }
    }

    /// What the person confirmed: the sheet's purpose and the address it ends on.
    nonisolated struct Confirmation: Hashable, Sendable {
        /// What confirming the sheet did.
        let purpose: Purpose
        /// The address the sheet ends on.
        let address: Address
    }

    /// What confirming the sheet does.
    let purpose: Purpose
    /// The pasted text without the spaces and line breaks around it.
    private(set) var text = ""
    /// The pasted address, or `nil` when the pasted text isn't one.
    private(set) var address: Address?
    /// The account or contact already saved at the pasted address.
    private(set) var saved: Contact?
    /// Why the pasted text can't be used, or `nil` while there's nothing to explain.
    private(set) var rejection: RecipientRejection?
    /// What to check about the pasted address before going on.
    private(set) var warnings: [RecipientWarning] = []
    /// The name the person types; spaces around it are ignored.
    var name: String
    /// Counts rejected pastes, so each one signals again while the same rejection stays on screen.
    private(set) var rejectionCount = 0
    /// What the person confirmed; the sheet closes itself when it's set.
    private(set) var confirmation: Confirmation?
    private let contacts: ContactsModel

    /// Starts an empty sheet for a new payment.
    /// - Parameter contacts: The window's contacts, which check the address and save a named one.
    init(contacts: ContactsModel) {
        purpose = .payment
        name = ""
        self.contacts = contacts
    }

    /// Starts a sheet that saves an address as a contact.
    /// - Parameters:
    ///   - address: The address to save.
    ///   - contacts: The window's contacts, which save the new contact.
    init(savingContactAt address: Address, contacts: ContactsModel) {
        purpose = .addContact
        name = ""
        self.contacts = contacts
        check(address.value)
    }

    /// Whether the sheet needs a name: contacts do, payments don't.
    var requiresName: Bool { purpose == .addContact }

    /// Whether the sheet can be confirmed: a usable address, and a name when one is required.
    var canConfirm: Bool {
        guard address != nil, rejection == nil else { return false }
        return !requiresName || !trimmedName.isEmpty
    }

    /// Takes pasted text, ignoring the spaces and line breaks that a copy can bring along.
    /// - Parameter pasted: The pasteboard's text.
    func paste(_ pasted: String) {
        check(pasted.trimmingCharacters(in: .whitespacesAndNewlines))
        if rejection != nil { rejectionCount += 1 }
    }

    /// Saves a named address as a contact, then sets ``confirmation``; a payment to an unsaved address with no name,
    /// or to a saved one, saves nothing.
    func confirm() {
        guard canConfirm, let address else { return }
        if saved == nil, !trimmedName.isEmpty {
            contacts.save(Contact(name: trimmedName, address: address))
        }
        confirmation = Confirmation(purpose: purpose, address: address)
    }

    /// Takes text and checks it once, so typing a name doesn't decode the address or look for look-alikes again.
    /// - Parameter text: The text without the spaces and line breaks around it.
    private func check(_ text: String) {
        self.text = text
        address = try? Address(text)
        saved = address.flatMap(contacts.saved(at:))
        rejection = rejection(of: text)
        warnings = rejection == nil
            ? address.map { RecipientClassifier.entry.warnings(for: $0, in: contacts.recipientContext) } ?? []
            : []
    }

    /// Why text can't be used as this sheet's address.
    /// - Parameter text: The checked text.
    /// - Returns: The rejection, or `nil` when the text is empty or usable.
    private func rejection(of text: String) -> RecipientRejection? {
        guard !text.isEmpty else { return nil }
        guard let address else { return .notAddress }
        if address == contacts.sendingAccount { return .sendingAccount }
        if purpose == .addContact, saved != nil { return .alreadySaved }
        return nil
    }

    /// The typed name without the spaces and line breaks around it.
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}
