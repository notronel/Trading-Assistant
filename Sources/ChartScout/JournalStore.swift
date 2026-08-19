import Combine
import CryptoKit
import Foundation

@MainActor
final class JournalStore: ObservableObject {
    @Published private(set) var entries: [JournalEntry] = []
    private let store = EncryptedJournalStore()
    init() { entries = (try? store.load()) ?? [] }
    func add(_ entry: JournalEntry) { entries.insert(entry, at: 0); persist() }
    func update(_ entry: JournalEntry, note: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].outcomeNote = note; persist()
    }
    func delete(_ offsets: IndexSet) { entries.remove(atOffsets: offsets); persist() }
    func deleteAll() { entries = []; try? store.clear() }
    private func persist() { try? store.save(entries) }
}

struct EncryptedJournalStore {
    private let keyStore = KeychainStore(service: "com.chartscout.journal")
    private var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "ChartScout/journal.bin") }
    func load() throws -> [JournalEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let data = try AES.GCM.open(box, using: try key())
        return try JSONDecoder().decode([JournalEntry].self, from: data)
    }
    func save(_ entries: [JournalEntry]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        let box = try AES.GCM.seal(data, using: try key())
        try box.combined!.write(to: url, options: .atomic)
    }
    func clear() throws { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
    private func key() throws -> SymmetricKey {
        if let stored = keyStore.read(account: "encryption-key"), let data = Data(base64Encoded: stored) { return SymmetricKey(data: data) }
        let data = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        try keyStore.save(data.base64EncodedString(), account: "encryption-key")
        return SymmetricKey(data: data)
    }
}
