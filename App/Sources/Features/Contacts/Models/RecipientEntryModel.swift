import Foundation
import Observation
import Transactions

/// Owns one recipient sheet: a pasted address and an optional name, for a new payment, a new contact, or an edit.
///
/// The sheet checks each address against the lists it's given; once the person confirms, its owner saves the contact
/// that ``confirmation`` carries.
@MainActor
@Observable
final class RecipientEntryModel: Identifiable {
    /// What confirming the sheet does.
    nonisolated enum Purpose: Hashable, Sendable {
        /// Pays the address; a name also saves it as a contact.
        case payment
        /// Saves the address as a contact under a name.
        case addContact
        /// Saves a contact's new name or address.
        case edit(Contact)

        /// The sheet's title.
        var title: LocalizedStringResource {
            switch self {
            case .payment: "New Payment"
            case .addContact: "Add Contact"
            case .edit: "Edit Contact"
            }
        }

        /// The name of the confirm button, which VoiceOver reads.
        var confirmationTitle: LocalizedStringResource {
            switch self {
            case .payment: "Continue"
            case .addContact, .edit: "Save Contact"
            }
        }

        /// The name field's placeholder, which says whether a name is needed.
        var namePlaceholder: LocalizedStringResource {
            switch self {
            case .payment: "Name (Optional)"
            case .addContact, .edit: "Name"
            }
        }
    }

    /// What the person confirmed: the sheet's purpose, the address it ends on, and the contact to save.
    nonisolated struct Confirmation: Hashable, Sendable {
        /// What confirming the sheet did.
        let purpose: Purpose
        /// The address the sheet ends on.
        let address: Address
        /// The new or edited contact the owner saves, or `nil` when there's nothing to save.
        var contact: Contact?
    }

    /// What confirming the sheet does.
    let purpose: Purpose
    /// The pasted text without the spaces and line breaks around it.
    private(set) var text = ""
    /// The pasted address, or `nil` when the pasted text isn't one.
    private(set) var address: Address?
    /// The account or contact already saved at the pasted address, other than the contact being edited.
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

    /// Starts an empty sheet for a new payment.
    init() {
        purpose = .payment
        name = ""
    }

    /// Starts a sheet that saves an address as a contact.
    /// - Parameters:
    ///   - address: The address to save.
    ///   - lists: The addresses the account can pay, which the address is checked against.
    init(savingContactAt address: Address, in lists: ContactLists) {
        purpose = .addContact
        name = ""
        check(address.value, in: lists)
    }

    /// Starts a sheet that edits a contact's name and address.
    /// - Parameters:
    ///   - contact: The contact to edit.
    ///   - lists: The addresses the account can pay, which the address is checked against.
    init(editing contact: Contact, in lists: ContactLists) {
        purpose = .edit(contact)
        name = contact.name
        check(contact.address.value, in: lists)
    }

    /// Whether the sheet needs a name: contacts do, payments don't.
    var requiresName: Bool { purpose != .payment }

    /// Whether the sheet can be confirmed: a usable address, and a name when one is required.
    var canConfirm: Bool {
        guard address != nil, rejection == nil else { return false }
        return !requiresName || !trimmedName.isEmpty
    }

    /// Takes pasted text, ignoring the spaces and line breaks that a copy can bring along.
    /// - Parameters:
    ///   - pasted: The pasteboard's text.
    ///   - lists: The addresses the account can pay, which the address is checked against.
    func paste(_ pasted: String, in lists: ContactLists) {
        check(pasted.trimmingCharacters(in: .whitespacesAndNewlines), in: lists)
        if rejection != nil { rejectionCount += 1 }
    }

    /// Sets ``confirmation`` with the contact the purpose saves: a new payment saves one only for an unsaved address
    /// with a name.
    func confirm() {
        guard canConfirm, let address else { return }
        var confirmation = Confirmation(purpose: purpose, address: address)
        if case .edit(var contact) = purpose {
            contact.name = trimmedName
            contact.address = address
            confirmation.contact = contact
        } else if saved == nil, !trimmedName.isEmpty {
            confirmation.contact = Contact(name: trimmedName, address: address)
        }
        self.confirmation = confirmation
    }

    /// Takes text and checks it once, so typing a name doesn't decode the address or look for look-alikes again.
    /// - Parameters:
    ///   - text: The text without the spaces and line breaks around it.
    ///   - lists: The addresses the account can pay, which the address is checked against.
    private func check(_ text: String, in lists: ContactLists) {
        self.text = text
        address = try? Address(text)
        saved = address.flatMap(lists.saved(at:)).flatMap { isEdited($0) ? nil : $0 }
        rejection = rejection(of: text, sendingAccount: lists.sendingAccount)
        warnings = rejection == nil
            ? address.map { RecipientClassifier.entry.warnings(for: $0, in: lists.recipientContext) } ?? []
            : []
    }

    /// Why text can't be used as this sheet's address.
    /// - Parameters:
    ///   - text: The checked text.
    ///   - sendingAccount: The account payments leave from, which can't be its own recipient.
    /// - Returns: The rejection, or `nil` when the text is empty or usable.
    private func rejection(of text: String, sendingAccount: Address) -> RecipientRejection? {
        guard !text.isEmpty else { return nil }
        guard let address else { return .notAddress }
        if address == sendingAccount { return .sendingAccount }
        if purpose != .payment, saved != nil { return .alreadySaved }
        return nil
    }

    /// Whether a saved contact is the one this sheet edits, so its own address isn't counted as already saved.
    /// - Parameter contact: A saved account or contact.
    /// - Returns: `true` when the sheet edits that contact.
    private func isEdited(_ contact: Contact) -> Bool {
        if case .edit(let edited) = purpose { edited.id == contact.id } else { false }
    }

    /// The typed name without the spaces and line breaks around it.
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}
