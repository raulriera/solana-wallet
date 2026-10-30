import Foundation
import Observation
import Transactions

/// A model that checks a pasted address and a name for a new payment, a new contact, or an edit.
@MainActor
@Observable
final class RecipientEntryModel: Identifiable {
    /// The action that confirming the sheet takes.
    nonisolated enum Purpose: Hashable, Sendable {
        /// Pays the address, and saves it as a contact when it has a name.
        case payment
        case addContact
        /// Saves a new name or address for this contact.
        case edit(Contact)

        var title: LocalizedStringResource {
            switch self {
            case .payment: "New Payment"
            case .addContact: "Add Contact"
            case .edit: "Edit Contact"
            }
        }

        /// The title of the confirm button.
        var confirmationTitle: LocalizedStringResource {
            switch self {
            case .payment: "Continue"
            case .addContact, .edit: "Save Contact"
            }
        }

        var namePlaceholder: LocalizedStringResource {
            switch self {
            case .payment: "Name (Optional)"
            case .addContact, .edit: "Name"
            }
        }
    }

    /// The purpose, address, and contact that the person confirmed.
    nonisolated struct Confirmation: Hashable, Sendable {
        let purpose: Purpose
        let address: Address
        /// The new or edited contact to save, or `nil` when there's nothing to save.
        var contact: Contact?
    }

    let purpose: Purpose
    /// The pasted text without the whitespace around it.
    private(set) var text = ""
    /// The pasted address, or `nil` when the pasted text isn't one.
    private(set) var address: Address?
    /// The account or contact already saved at the pasted address, other than the contact being edited.
    private(set) var saved: Contact?
    private(set) var rejection: RecipientRejection?
    private(set) var warnings: [RecipientWarning] = []
    var name: String
    private(set) var rejectionCount = 0
    private(set) var confirmation: Confirmation?

    /// Creates an empty model for a new payment.
    init() {
        purpose = .payment
        name = ""
    }

    /// Creates a model that saves an address as a contact.
    ///
    /// - Parameters:
    ///   - address: The address to save.
    ///   - lists: The lists to check the address against.
    init(savingContactAt address: Address, in lists: ContactLists) {
        purpose = .addContact
        name = ""
        check(address.value, in: lists)
    }

    /// Creates a model that edits a contact's name and address.
    ///
    /// - Parameters:
    ///   - contact: The contact to edit.
    ///   - lists: The lists to check the address against.
    init(editing contact: Contact, in lists: ContactLists) {
        purpose = .edit(contact)
        name = contact.name
        check(contact.address.value, in: lists)
    }

    var requiresName: Bool { purpose != .payment }

    var canConfirm: Bool {
        guard address != nil, rejection == nil else { return false }
        return !requiresName || !trimmedName.isEmpty
    }

    /// Checks pasted text without the whitespace around it.
    ///
    /// - Parameters:
    ///   - pasted: The pasteboard's text.
    ///   - lists: The lists to check the address against.
    func paste(_ pasted: String, in lists: ContactLists) {
        check(pasted.trimmingCharacters(in: .whitespacesAndNewlines), in: lists)
        if rejection != nil { rejectionCount += 1 }
    }

    /// Sets ``confirmation`` with the contact to save.
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

    /// Checks text as the sheet's address.
    ///
    /// - Parameters:
    ///   - text: The text without the whitespace around it.
    ///   - lists: The lists to check the address against.
    private func check(_ text: String, in lists: ContactLists) {
        self.text = text
        address = try? Address(text)
        saved = address.flatMap(lists.saved(at:)).flatMap { isEdited($0) ? nil : $0 }
        rejection = rejection(of: text, sendingAccount: lists.sendingAccount)
        warnings = rejection == nil
            ? address.map { RecipientClassifier.entry.warnings(for: $0, in: lists.recipientContext) } ?? []
            : []
    }

    /// Returns why text can't be the sheet's address.
    ///
    /// - Parameters:
    ///   - text: The checked text.
    ///   - sendingAccount: The address of the account that pays.
    /// - Returns: The rejection, or `nil` when the text is empty or usable.
    private func rejection(of text: String, sendingAccount: Address) -> RecipientRejection? {
        guard !text.isEmpty else { return nil }
        guard let address else { return .notAddress }
        if address == sendingAccount { return .sendingAccount }
        if purpose != .payment, saved != nil { return .alreadySaved }
        return nil
    }

    /// Returns whether the sheet edits a saved contact.
    ///
    /// - Parameter contact: A saved account or contact.
    /// - Returns: `true` when the sheet edits that contact.
    private func isEdited(_ contact: Contact) -> Bool {
        if case .edit(let edited) = purpose { edited.id == contact.id } else { false }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}
