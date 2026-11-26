//
//  SharedVault.swift
//  Title Capitalizr (app, share extension, widgets)
//
//  History, favourites, the custom dictionary and the Pro flag, shared between the app and
//  its extensions through a keychain access group (App Groups can't be provisioned with the
//  App Store Connect API key this project is built with). Falls back to the process's own
//  UserDefaults when the keychain group isn't available (unit tests, unsigned builds).
//

import Foundation
import Security
import TitleCaseKit

struct HistoryEntry: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var input: String
    var output: String
    var guide: StyleGuide
    var date = Date()
    var favorite = false
}

struct SharedSnapshot: Codable, Equatable {
    var history: [HistoryEntry] = []
    var dictionary = CustomDictionary()
    var isPro = false
    var lastGuide: StyleGuide = .mla
    /// Text handed over by the share extension or a widget, picked up once by the app.
    var pendingInput: String?

    static let historyLimit = 200

    var favorites: [HistoryEntry] { history.filter(\.favorite) }
    var recents: [HistoryEntry] { history.filter { !$0.favorite } }

    /// Adds an entry at the top, merging with an identical earlier one (keeps its favourite flag).
    mutating func record(input: String, output: String, guide: StyleGuide) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !output.isEmpty else { return }
        var entry = HistoryEntry(input: trimmed, output: output, guide: guide)
        if let i = history.firstIndex(where: { $0.output == output && $0.guide == guide }) {
            entry.favorite = history[i].favorite
            entry.id = history[i].id
            history.remove(at: i)
        }
        history.insert(entry, at: 0)
        // Favourites are never trimmed away.
        while history.count > Self.historyLimit, let last = history.lastIndex(where: { !$0.favorite }) {
            history.remove(at: last)
        }
    }
}

enum SharedVault {
    static let accessGroup = "Z64KRUX3W3.com.johnseong.titlecapitalizr.shared"
    static let service = "com.johnseong.titlecapitalizr.shared"
    static let account = "snapshot"
    private static let fallbackKey = "tc.sharedSnapshot"

    static func load() -> SharedSnapshot {
        if let data = keychainData(), let s = try? JSONDecoder().decode(SharedSnapshot.self, from: data) { return s }
        if let data = UserDefaults.standard.data(forKey: fallbackKey),
           let s = try? JSONDecoder().decode(SharedSnapshot.self, from: data) { return s }
        return SharedSnapshot()
    }

    static func save(_ snapshot: SharedSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if !writeKeychain(data) { UserDefaults.standard.set(data, forKey: fallbackKey) }
    }

    static func update(_ change: (inout SharedSnapshot) -> Void) {
        var s = load()
        change(&s)
        save(s)
    }

    private static func baseQuery() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        #if os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }

    private static func keychainData() -> Data? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func writeKeychain(_ data: Data) -> Bool {
        let q = baseQuery()
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

/// Deep links shared by widgets, the share extension and the app.
enum TCLink {
    static let scheme = "titlecapitalizr"
    static func open(guide: StyleGuide? = nil, mode: String? = nil) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "open"
        var items: [URLQueryItem] = []
        if let guide { items.append(.init(name: "guide", value: guide.rawValue)) }
        if let mode { items.append(.init(name: "mode", value: mode)) }
        c.queryItems = items.isEmpty ? nil : items
        return c.url!
    }
    static func entry(_ id: UUID) -> URL { URL(string: "\(scheme)://history?id=\(id.uuidString)")! }
}
