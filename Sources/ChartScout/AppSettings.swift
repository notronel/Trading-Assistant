import Combine
import Carbon.HIToolbox
import Foundation
import Security

final class AppSettings: ObservableObject {
    @Published var model: String { didSet { defaults.set(model, forKey: "model") } }
    @Published var shortcut: ShortcutChoice { didSet { defaults.set(shortcut.rawValue, forKey: "shortcut") } }
    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "com.chartscout.api")

    init() {
        model = defaults.string(forKey: "model") ?? "gpt-4.1-mini"
        shortcut = ShortcutChoice(rawValue: defaults.string(forKey: "shortcut") ?? "commandShiftSpace") ?? .commandShiftSpace
    }
    var hasAPIKey: Bool { !(apiKey?.isEmpty ?? true) }
    var apiKey: String? { keychain.read(account: "openai-api-key") }
    func saveAPIKey(_ value: String) throws { try keychain.save(value, account: "openai-api-key") }
}

enum ShortcutChoice: String, CaseIterable, Identifiable {
    case commandShiftSpace, commandOptionSpace, controlOptionSpace
    var id: String { rawValue }
    var title: String { switch self { case .commandShiftSpace: "⌘⇧Space"; case .commandOptionSpace: "⌘⌥Space"; case .controlOptionSpace: "⌃⌥Space" } }
    var carbonModifiers: UInt32 { switch self { case .commandShiftSpace: UInt32(cmdKey | shiftKey); case .commandOptionSpace: UInt32(cmdKey | optionKey); case .controlOptionSpace: UInt32(controlKey | optionKey) } }
}

enum KeychainError: LocalizedError { case unexpectedStatus(OSStatus)
    var errorDescription: String? { "Unable to access Keychain." }
}

struct KeychainStore {
    let service: String
    func read(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }
}
