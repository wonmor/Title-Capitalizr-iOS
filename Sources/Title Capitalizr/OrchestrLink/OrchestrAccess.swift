import Foundation
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Orchestr plans + entitlement for one app (2026-11-24, Orchestr All Access).
///
/// Paywall order (fixed): All Access (annual, monthly), then the app's bundle (Orchestr Pro or Orchestr Education,
/// annual, monthly) when it belongs to one, then the app's own plans. Restore covers all of them.
/// Entitlement: own Pro OR the app's bundle OR All Access, each either bought here (StoreKit) or carried by a linked
/// Orchestr account token (verified offline).
///
///   let access = OrchestrAccess(link: OrchestrLink(app: "flybycode", appName: "Orchestr: Fly-by-Code"),
///                               bundle: .pro, ownProductIDs: ["com.orchestrsim.ig.pro.yearly", "com.orchestrsim.ig.pro.monthly"])
///   await access.load()           // products in paywall order + entitlement
///   access.isPro                  // gate
///   try await access.purchase(row.product)
///   await access.restore()
///   let updates = access.observeTransactions()   // keep the Task for the app's lifetime
public enum OrchestrPlanKind: String, Sendable {
    case allaccess, bundle, own
}

public enum OrchestrPaywall {
    /// Product ids in paywall order. `bundle` nil = an app outside Orchestr Pro / Education (All Access only).
    public static func orderedProductIDs(bundle: OrchestrBundle?, bundleId: String, own: [String]) -> [String] {
        var ids: [String] = []
        let aa = OrchestrProducts.appStoreIDs(.allaccess, bundleId: bundleId)
        ids += [aa.annual, aa.monthly]
        if let b = bundle, b != .allaccess {
            let p = OrchestrProducts.appStoreIDs(b, bundleId: bundleId)
            ids += [p.annual, p.monthly]
        }
        ids += own.filter { !ids.contains($0) }
        return ids
    }

    public static func kind(of productId: String) -> OrchestrPlanKind {
        switch OrchestrProducts.bundle(of: productId) {
        case .allaccess?: return .allaccess
        case .some: return .bundle
        case nil: return .own
        }
    }

    /// "A, B and C" (no middle dots or bullets anywhere in paywall copy).
    public static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    public static func title(_ bundle: OrchestrBundle) -> String {
        switch bundle {
        case .allaccess: return "Orchestr All Access"
        case .pro: return "Orchestr Pro"
        case .education: return "Orchestr Education"
        }
    }

    /// Row description (App Store 3.1.3(b): never web prices, links to web checkout, or "buy it in another app").
    public static func subtitle(_ bundle: OrchestrBundle) -> String {
        let link = "Use it in your other apps by linking a free Orchestr account."
        switch bundle {
        case .allaccess: return "Pro in every Orchestr app: aviation, science and productivity. \(link)"
        case .pro: return "Unlocks Pro in \(list(OrchestrProducts.proApps)). \(link)"
        case .education: return "Unlocks Pro in \(list(OrchestrProducts.educationApps)). \(link)"
        }
    }

    /// SF Symbol glyph per row (glyphs, never plain shapes).
    public static func glyph(_ kind: OrchestrPlanKind, bundle: OrchestrBundle?) -> String {
        switch kind {
        case .allaccess: return "infinity"
        case .bundle: return bundle == .education ? "graduationcap" : "airplane"
        case .own: return "checkmark.seal"
        }
    }
}

#if canImport(StoreKit)
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
@MainActor
public final class OrchestrAccess: ObservableObject {
    public struct Row: Identifiable {
        public var id: String { product.id }
        public let product: Product
        public let kind: OrchestrPlanKind
        public let title: String
        public let subtitle: String?
        public let glyph: String
        /// "/ month", "/ year" (empty for non-subscriptions such as a lifetime unlock).
        public let periodText: String
    }

    @Published public private(set) var rows: [Row] = []
    @Published public private(set) var isPro = false
    /// What grants Pro right now (for Settings): "allaccess" | "pro" | "education" | "own" | nil.
    @Published public private(set) var grantedBy: String?
    @Published public private(set) var ownedProductIDs: Set<String> = []

    public let link: OrchestrLink
    public let bundle: OrchestrBundle?
    public let ownProductIDs: [String]
    public let bundleId: String

    public init(link: OrchestrLink, bundle: OrchestrBundle?, ownProductIDs: [String],
                bundleId: String = Bundle.main.bundleIdentifier ?? "") {
        self.link = link
        self.bundle = bundle == .allaccess ? nil : bundle
        self.ownProductIDs = ownProductIDs
        self.bundleId = bundleId
    }

    public var productIDs: [String] { OrchestrPaywall.orderedProductIDs(bundle: bundle, bundleId: bundleId, own: ownProductIDs) }

    public func load() async {
        let ids = productIDs
        let products = (try? await Product.products(for: ids)) ?? []
        rows = ids.compactMap { id in
            guard let p = products.first(where: { $0.id == id }) else { return nil }
            let kind = OrchestrPaywall.kind(of: id)
            let b = OrchestrProducts.bundle(of: id)
            return Row(product: p, kind: kind,
                       title: b.map { OrchestrPaywall.title($0) } ?? p.displayName,
                       subtitle: b.map { OrchestrPaywall.subtitle($0) } ?? (p.description.isEmpty ? nil : p.description),
                       glyph: OrchestrPaywall.glyph(kind, bundle: bundle),
                       periodText: Self.periodText(p))
        }
        await refreshEntitlement()
    }

    static func periodText(_ p: Product) -> String {
        guard let s = p.subscription?.subscriptionPeriod else { return "" }
        switch s.unit {
        case .year: return s.value == 1 ? "/ year" : "/ \(s.value) years"
        case .month: return s.value == 1 ? "/ month" : "/ \(s.value) months"
        case .week: return s.value == 1 ? "/ week" : "/ \(s.value) weeks"
        case .day: return s.value == 1 ? "/ day" : "/ \(s.value) days"
        @unknown default: return ""
        }
    }

    /// Own Pro OR the app's bundle OR All Access (local StoreKit or linked account).
    public func refreshEntitlement() async {
        var owned = Set<String>()
        let mine = Set(productIDs)
        for await r in Transaction.currentEntitlements {
            guard case .verified(let t) = r, t.revocationDate == nil, mine.contains(t.productID) else { continue }
            if let e = t.expirationDate, e <= Date() { continue }
            owned.insert(t.productID)
        }
        ownedProductIDs = owned
        let localAA = owned.contains { OrchestrProducts.isBundleProduct($0, .allaccess) }
        let localBundle = bundle.map { b in owned.contains { OrchestrProducts.isBundleProduct($0, b) } } ?? false
        let localOwn = owned.contains { OrchestrProducts.bundle(of: $0) == nil }
        if localAA || link.grants(.allaccess) { grantedBy = "allaccess" }
        else if let b = bundle, localBundle || link.grants(b) { grantedBy = b.rawValue }
        else if localOwn { grantedBy = "own" }
        else { grantedBy = nil }
        isPro = grantedBy != nil
    }

    /// Buys with the linked account as appAccountToken; claims bundle purchases on the account when linked.
    @discardableResult
    public func purchase(_ product: Product) async throws -> Bool {
        var options: Set<Product.PurchaseOption> = []
        if let token = link.accountToken { options.insert(.appAccountToken(token)) }
        let result = try await product.purchase(options: options)
        switch result {
        case .success(let v):
            guard case .verified(let t) = v else { return false }
            await t.finish()
            if OrchestrProducts.bundle(of: t.productID) != nil, link.isLinked {
                _ = try? await link.claim(appStoreJWS: v.jwsRepresentation)
            }
            await refreshEntitlement()
            return true
        case .pending, .userCancelled: return false
        @unknown default: return false
        }
    }

    /// Restore Purchases: covers own plans, the bundle and All Access; re-claims bundle purchases when linked.
    public func restore() async {
        try? await AppStore.sync()
        await link.refresh()
        await link.claimLocalPurchasesIfLinked([.allaccess] + (bundle.map { [$0] } ?? []))
        await refreshEntitlement()
    }

    /// Launch / foreground: refresh the token, claim local bundle purchases, recompute.
    public func onLaunch() async {
        await link.refresh()
        await link.claimLocalPurchasesIfLinked([.allaccess] + (bundle.map { [$0] } ?? []))
        await load()
    }

    public func observeTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await r in Transaction.updates {
                if case .verified(let t) = r { await t.finish() }
                await self?.refreshEntitlement()
            }
        }
    }
}

#if canImport(SwiftUI) && !os(watchOS)
/// Minimal paywall rows in the required order. Apps may style their own; keep the order and the copy.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, *)
public struct OrchestrPlanRows: View {
    @ObservedObject var access: OrchestrAccess
    var onSelect: (OrchestrAccess.Row) -> Void

    public init(access: OrchestrAccess, onSelect: @escaping (OrchestrAccess.Row) -> Void) {
        self.access = access
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 10) {
            ForEach(access.rows) { row in
                Button { onSelect(row) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.glyph).font(.title3).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.title).font(.headline)
                                Spacer()
                                Text("\(row.product.displayPrice) \(row.periodText)").font(.subheadline.monospacedDigit())
                            }
                            if let s = row.subtitle { Text(s).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(row.kind == .allaccess ? Color.accentColor : Color.secondary.opacity(0.3),
                                                                    lineWidth: row.kind == .allaccess ? 2 : 1))
                .disabled(access.ownedProductIDs.contains(row.id))
                .accessibilityLabel("\(row.title), \(row.product.displayPrice) \(row.periodText)")
            }
        }
    }
}
#endif
#endif
