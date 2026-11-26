import Foundation
import Security
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Orchestr account link for an app (RFC 8628 device link against orchaerospace.com).
///
///   let link = OrchestrLink(app: "atomizer", appName: "Atomizer AR")
///   let code = try await link.start()          // show code.userCode, open code.url
///   try await link.waitForApproval(code)        // polls until linked / denied / expired
///   link.grants(.education)                     // offline check (signature + device + expiry); All Access counts
///   await link.refresh()                        // on launch / foreground
///   try await link.claim(transaction.jwsRepresentation)   // after an Orchestr purchase / restore
///   await link.unlink()
///   OrchestrLink.deleteAccountURL               // Settings > Delete Orchestr account (5.1.1(v))
///
/// The verification page opened by `start()` (`...&from=app`) only signs in
/// and approves: it never shows prices or checkout, so it is safe to open
/// from iOS apps (no web-purchase steering).
@MainActor
public final class OrchestrLink: ObservableObject {
    public static let api = URL(string: "https://www.orchaerospace.com")!
    public static let deleteAccountURL = URL(string: "https://orchaerospace.com/jebs/link?delete=1&from=app")!

    public struct Code: Equatable, Sendable {
        public let userCode: String
        public let url: URL
        let deviceCode: String
        let interval: TimeInterval
        let expires: Date
    }

    public enum LinkError: Error, Equatable {
        case server(String)
        case denied
        case expired
        case linkedToOtherAccount(String?)
        case notLinked
    }

    /// Current verified claims (nil when not linked).
    @Published public private(set) var claims: OrchestrClaims?

    public let app: String
    public let appName: String
    public let deviceId: String
    private let keys: [String]
    private let session: URLSession
    private let keychainService: String

    public init(app: String, appName: String, keys: [String] = OrchestrToken.productionKeys,
                session: URLSession = .shared, keychainService: String = "com.orchestr.link") {
        self.app = app
        self.appName = appName
        self.keys = keys
        self.session = session
        self.keychainService = keychainService
        if let id = Keychain.get(keychainService, "deviceId"), id.count >= 8 {
            deviceId = id
        } else {
            let id = "\(app)-\(UUID().uuidString.lowercased())"
            Keychain.set(keychainService, "deviceId", id)
            deviceId = id
        }
        claims = token.flatMap { OrchestrToken.verify($0, keys: keys) }
    }

    public var token: String? { Keychain.get(keychainService, "token") }
    public var isLinked: Bool { claims != nil }
    /// Orchestr account id: pass as StoreKit `appAccountToken` when buying while linked.
    public var accountToken: UUID? { claims.flatMap { UUID(uuidString: $0.sub) } }

    public func grants(_ bundle: OrchestrBundle, now: Date = Date()) -> Bool {
        OrchestrToken.grants(claims, bundle, deviceId: deviceId, now: now)
    }

    private func store(_ t: String?) {
        if let t, let c = OrchestrToken.verify(t, keys: keys), c.did == deviceId {
            Keychain.set(keychainService, "token", t)
            claims = c
        } else {
            Keychain.delete(keychainService, "token")
            claims = nil
        }
    }

    // MARK: HTTP

    private func post(_ path: String, _ body: [String: Any], auth: Bool = false) async throws -> (Int, [String: Any]) {
        var req = URLRequest(url: Self.api.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let t = token {
            req.setValue("Jpd1 \(t)", forHTTPHeaderField: "Authorization")
            req.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (code, json)
    }

    private var platform: String {
        #if os(visionOS)
        return "visionos"
        #elseif os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "apple"
        #endif
    }

    // MARK: Link

    public func start() async throws -> Code {
        let (status, j) = try await post("api/pro/device/start", [
            "device_id": deviceId, "device_name": "\(appName) on \(deviceKind)", "platform": platform, "app": app,
        ])
        guard status == 200, let dc = j["device_code"] as? String, let uc = j["user_code"] as? String,
              let u = (j["verification_uri_complete"] as? String).flatMap(URL.init(string:)) else {
            throw LinkError.server((j["message"] as? String) ?? "Could not start linking (\(status)).")
        }
        let interval = (j["interval"] as? Double) ?? 5
        let ttl = (j["expires_in"] as? Double) ?? 600
        return Code(userCode: uc, url: u, deviceCode: dc, interval: max(3, interval), expires: Date().addingTimeInterval(ttl))
    }

    /// Polls until approved (stores the token), denied or expired. Cancel the Task to stop.
    public func waitForApproval(_ code: Code) async throws {
        var interval = code.interval
        while Date() < code.expires {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard let (_, j) = try? await post("api/pro/device/poll", ["device_code": code.deviceCode, "device_id": deviceId]) else { continue }
            switch j["status"] as? String {
            case "approved":
                store(j["token"] as? String)
                if claims == nil { throw LinkError.server("The link answer could not be verified.") }
                return
            case "slow_down": interval *= 2
            case "denied": throw LinkError.denied
            case "expired": throw LinkError.expired
            default: break
            }
        }
        throw LinkError.expired
    }

    /// Fresh claims (launch / foreground). Offline: keeps the stored token. Revoked: unlinks.
    public func refresh() async {
        guard let t = token else { return }
        guard let (status, j) = try? await post("api/pro/device/refresh", ["token": t, "device_id": deviceId]) else { return }
        if status == 200, let nt = j["token"] as? String { store(nt) }
        else if status == 401 { store(nil) }
    }

    public func unlink() async {
        if let t = token { _ = try? await post("api/pro/device/signout", ["token": t, "device_id": deviceId]) }
        store(nil)
    }

    /// Attach an Orchestr purchase (StoreKit 2 `jwsRepresentation`) to the linked account.
    @discardableResult
    public func claim(appStoreJWS jws: String) async throws -> [String: Any] {
        guard token != nil else { throw LinkError.notLinked }
        let (status, j) = try await post("api/orchestr/claim", ["store": "appstore", "jws": jws], auth: true)
        if status == 200 {
            if let nt = j["token"] as? String { store(nt) }
            return j
        }
        if status == 409 { throw LinkError.linkedToOtherAccount(j["email"] as? String) }
        if status == 401 { store(nil); throw LinkError.notLinked }
        throw LinkError.server((j["error"] as? String) ?? "claim failed (\(status))")
    }

    private var deviceKind: String {
        #if os(visionOS)
        return "Apple Vision Pro"
        #elseif canImport(UIKit) && !os(watchOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #elseif os(macOS)
        return "Mac"
        #else
        return "Apple device"
        #endif
    }
}

#if canImport(StoreKit)
public extension OrchestrLink {
    /// Verified, unrevoked, unexpired Orchestr transaction of this app on the device's Apple ID, if any.
    static func localBundleTransaction(_ bundle: OrchestrBundle) async -> (jws: String, productID: String)? {
        for await r in Transaction.currentEntitlements {
            guard case .verified(let t) = r, t.revocationDate == nil,
                  OrchestrProducts.isBundleProduct(t.productID, bundle) else { continue }
            if let e = t.expirationDate, e <= Date() { continue }
            return (r.jwsRepresentation, t.productID)
        }
        return nil
    }

    /// Claim the device's Orchestr purchase if linked (after a purchase, a restore, or on launch).
    func claimLocalPurchaseIfLinked(_ bundle: OrchestrBundle) async {
        guard isLinked, let tx = await Self.localBundleTransaction(bundle) else { return }
        _ = try? await claim(appStoreJWS: tx.jws)
    }

    /// Claim every local Orchestr purchase of this app (All Access and the app's bundle) if linked.
    func claimLocalPurchasesIfLinked(_ bundles: [OrchestrBundle] = OrchestrBundle.allCases) async {
        guard isLinked else { return }
        for b in bundles {
            if let tx = await Self.localBundleTransaction(b) { _ = try? await claim(appStoreJWS: tx.jws) }
        }
    }
}
#endif

/// Minimal generic-password Keychain wrapper (this device only, after first unlock).
enum Keychain {
    static func query(_ service: String, _ key: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        #if os(macOS)
        // Without this, macOS uses the legacy login keychain and blocks launch on an access prompt when another
        // Orchestr app created the item first (seen in Point Fluid / Point Hydrology, 2026-11-09).
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }

    static func get(_ service: String, _ key: String) -> String? {
        var q = query(service, key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ service: String, _ key: String, _ value: String) {
        delete(service, key)
        var q = query(service, key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ service: String, _ key: String) {
        SecItemDelete(query(service, key) as CFDictionary)
    }
}
