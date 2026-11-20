import Storage
import Testing

@Suite(.timeLimit(.minutes(1)))
struct MemoryItemTests {
    @Test
    func `A change is saved to the other storage`() async throws {
        let saved = StoredValue(["old"])
        let item = MemoryItem(savingTo: saved)

        try await item.update { $0?.append("new") }

        #expect(await saved.value == ["old", "new"])
        #expect(await saved.loads == 1)
    }

    @Test
    func `A change that can't be saved is kept in memory`() async throws {
        let item = MemoryItem(savingTo: StoredValue<[String]>(failsSaving: true))

        try await item.update { $0 = ["kept"] }

        #expect(await item.load() == ["kept"])
    }

    @Test
    func `A value that can't be read starts empty and the next save replaces it`() async {
        let saved = StoredValue(["old"], unreadable: true)
        let item = MemoryItem(savingTo: saved)

        #expect(await item.load() == nil)
        await item.save(["new"])

        #expect(await saved.value == ["new"])
    }
}
