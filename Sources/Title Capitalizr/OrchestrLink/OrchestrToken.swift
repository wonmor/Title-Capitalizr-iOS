import CryptoKit
import Foundation

/// Orchestr device token ("jpd1"): `jpd1.<claims base64url>.<Ed25519 signature base64url>`,
/// signed by orchaerospace.com (key id ad1d890f). Verified offline.
///
/// Claims the apps use (unknown claims are ignored):
///   sub   Orchestr account id (UUID) - also the StoreKit appAccountToken
///   em    masked email for Settings ("j***n@gmail.com")
///   did   device id the token was issued to (must equal ours)
///   edu / eexp   Orchestr Education active / expiry (unix s)
///   orch / oexp  Orchestr Pro (aviation) active / expiry (unix s)
///   aa / aaexp   Orchestr All Access active / expiry (unix s). The server also sets orch / edu for it;
///                `grants` accepts aa directly as well (older or newer servers).
public struct OrchestrClaims: Codable, Equatable, Sendable {
    public var v: Int
    public var sub: String
    public var em: String?
    public var did: String
    public var jti: String
    public var iat: Double
    public var exp: Double
    public var ent: Bool
    public var orch: Bool?
    public var oexp: Double?
    public var edu: Bool?
    public var eexp: Double?
    public var aa: Bool?
    public var aaexp: Double?
}

public enum OrchestrBundle: String, Sendable, CaseIterable {
    /// Orchestr All Access: Pro in every Orchestr app (includes Orchestr Pro and Orchestr Education).
    case allaccess
    /// Orchestr Pro: the aviation apps.
    case pro
    /// Orchestr Education: the science / education apps.
    case education
}

public enum OrchestrToken {
    public static let prefix = "jpd1"
    /// Offline grace after expiry (an app that could not refresh for a while).
    public static let offlineGrace: TimeInterval = 7 * 24 * 3600
    /// Production public key, id ad1d890f (orchaerospace.com JEBS_DEVICE_SIGNING_KEY).
    public static let productionKeys = ["Mb7V6Xg7RaWUsq7lmchT+P/FC6Xtrk6Vyh9Q9r2X4pQ="]

    static func b64url(_ s: Substring) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    /// Claims of a correctly signed token, or nil (expiry is checked by `grants`).
    public static func verify(_ token: String, keys: [String] = productionKeys) -> OrchestrClaims? {
        guard token.count <= 4096 else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == prefix,
              let body = b64url(parts[1]), let sig = b64url(parts[2]), sig.count == 64 else { return nil }
        let msg = Data("\(parts[0]).\(parts[1])".utf8)
        let ok = keys.contains { k in
            guard let raw = Data(base64Encoded: k),
                  let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
            return pub.isValidSignature(sig, for: msg)
        }
        guard ok, let c = try? JSONDecoder().decode(OrchestrClaims.self, from: body), c.v == 1 else { return nil }
        return c
    }

    /// True when the (verified) claims unlock `bundle` on this device right now.
    public static func grants(_ c: OrchestrClaims?, _ bundle: OrchestrBundle, deviceId: String, now: Date = Date()) -> Bool {
        guard let c, c.did == deviceId else { return false }
        let t = now.timeIntervalSince1970
        func live(_ flag: Bool?, _ exp: Double?) -> Bool { flag == true && (exp ?? 0) > 0 && t < (exp ?? 0) + offlineGrace }
        let allAccess = live(c.aa, c.aaexp)
        switch bundle {
        case .allaccess: return allAccess
        case .education: return allAccess || live(c.edu, c.eexp)
        case .pro: return allAccess || live(c.orch, c.oexp)
        }
    }
}

/// Store product ids of the bundles.
public enum OrchestrProducts {
    /// App Store: `<bundleId>.education.monthly|annual` (Orchestr Education),
    /// `<bundleId>.orchestr.monthly|annual` (Orchestr Pro).
    public static func infix(_ bundle: OrchestrBundle) -> String {
        switch bundle {
        case .allaccess: return "allaccess"
        case .education: return "education"
        case .pro: return "orchestr"
        }
    }

    /// App Store product ids may not contain "-": these bundle ids use a prefix (same table as the server).
    public static let productPrefix = ["com.johnseong.dock-it": "com.johnseong.dockit", "com.johnseong.uci-courses": "com.johnseong.ucicourses"]

    /// `<prefix>.allaccess.*` (All Access), `<prefix>.education.*` (Education), `<prefix>.orchestr.*` (Pro);
    /// prefix = bundle id unless listed in `productPrefix`.
    public static func appStoreIDs(_ bundle: OrchestrBundle, bundleId: String = Bundle.main.bundleIdentifier ?? "") -> (monthly: String, annual: String) {
        let i = infix(bundle)
        let px = productPrefix[bundleId] ?? bundleId
        return ("\(px).\(i).monthly", "\(px).\(i).annual")
    }

    public static func isBundleProduct(_ productId: String, _ bundle: OrchestrBundle) -> Bool {
        productId.contains(".\(infix(bundle)).") && (productId.hasSuffix(".monthly") || productId.hasSuffix(".annual"))
    }

    /// Bundle of a product id, if it is an Orchestr bundle product.
    public static func bundle(of productId: String) -> OrchestrBundle? {
        OrchestrBundle.allCases.first { isBundleProduct(productId, $0) }
    }

    /// Google Play subscription product (base plans `monthly`, `annual`). All Access has no trial offer.
    public static func playProductID(_ bundle: OrchestrBundle) -> String {
        switch bundle {
        case .allaccess: return "orchestr_allaccess"
        case .education: return "orchestr_education"
        case .pro: return "orchestr_pro"
        }
    }

    /// Apps named on the paywall rows. Keep in sync with the server catalogue (orchaerospace-site core.ts).
    public static let educationApps = ["Atomizer AR", "Electronify", "ElectronVisualized", "OrchFold", "Point Fluid Lab",
                                       "MolDock", "OrchPCB", "Orch-OR Visualizer", "Inside LLM"]
    public static let proApps = ["Jeb's Horizon EFB", "Jeb's Electron EFB", "Jeb's Sim EFB", "Jeb's A320 Checklist", "A220 Guide",
                                 "PSTAR Trainer", "Orchestr: Fly-by-Code", "Jeb's Flight Reference", "SIGNAL", "PropBalance"]
}
