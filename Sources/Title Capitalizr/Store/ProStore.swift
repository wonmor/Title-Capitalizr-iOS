//
//  ProStore.swift
//  Title Capitalizr
//
//  StoreKit 2 for "Title Capitalizr Pro" plus Orchestr All Access (OrchestrLink drop-in).
//  Pro = own Pro (yearly or lifetime) OR Orchestr All Access, bought here or carried by a
//  linked Orchestr account. Derived on launch, on every transaction update and when the
//  app returns to the foreground. The flag is mirrored into the shared vault so the share
//  extension and the widgets can read it.
//
//  Free: title case in Title Case, MLA and APA, history and favourites, the basic text tools
//  (UPPER, lower, Sentence case, trim spaces, remove line breaks), spelling and grammar checks.
//  Pro: every style guide, batch mode, the developer text tools, custom dictionary, Shortcuts
//  actions and the Mac Services menu, Apple Intelligence polish, and the essay formatter.
//

import Combine
import Foundation
import StoreKit
import SwiftUI
import TitleCaseKit

enum ProProductID {
    static let yearly = "com.johnseong.titlecapitalizr.pro.yearly"
    static let lifetime = "com.johnseong.titlecapitalizr.pro.lifetime"
    static let own = [yearly, lifetime]
    static let allAccessAnnual = "com.johnseong.titlecapitalizr.allaccess.annual"
    static let allAccessMonthly = "com.johnseong.titlecapitalizr.allaccess.monthly"
    static let all = [allAccessAnnual, allAccessMonthly] + own
}

/// Pure decision for which local entitlements unlock Pro (unit tested).
enum ProEntitlementPolicy {
    struct Snapshot: Equatable {
        let productID: String
        let expirationDate: Date?
        let revocationDate: Date?
    }

    static func isPro(_ snapshots: [Snapshot], now: Date) -> Bool {
        snapshots.contains { s in
            guard ProProductID.all.contains(s.productID), s.revocationDate == nil else { return false }
            if let exp = s.expirationDate { return exp > now }
            return true
        }
    }
}

/// What Pro unlocks, used by the paywall and by locked controls.
enum ProFeature: String, CaseIterable, Identifiable {
    case guides, batch, tools, dictionary, shortcuts, ai, essay
    var id: String { rawValue }

    var title: String {
        switch self {
        case .guides: return "All ten style guides: AP, APA, Chicago, MLA, Bluebook, AMA, NYT, Wikipedia, sentence case and title case"
        case .batch: return "Batch mode for lists, file names and CSV columns"
        case .tools: return "camelCase, snake_case, kebab-case, slugs and smart quotes"
        case .dictionary: return "Custom dictionary for brand names and acronyms"
        case .shortcuts: return Platform.isMac ? "Shortcuts actions and the Services menu" : "Shortcuts actions and Siri"
        case .ai: return "Apple Intelligence headline polish and grammar fix"
        case .essay: return "Essay formatter with Word, PDF, RTF and text export"
        }
    }

    var systemImage: String {
        switch self {
        case .guides: return "books.vertical"
        case .batch: return "list.bullet.rectangle"
        case .tools: return "chevron.left.forwardslash.chevron.right"
        case .dictionary: return "character.book.closed"
        case .shortcuts: return "square.stack.3d.up"
        case .ai: return "sparkles"
        case .essay: return "doc.text"
        }
    }
}

@MainActor
final class ProStore: ObservableObject {
    static let shared = ProStore()

    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    let link = OrchestrLink(app: "titlecap", appName: "Title Capitalizr")
    let access: OrchestrAccess

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var trialEligible = false
    @Published private(set) var busy: String?
    @Published var message: String?
    /// Opens the paywall from anywhere (menus, Services, intents).
    @Published var paywallRequested = false

    private var updatesTask: Task<Void, Never>?
    private var forcedPro = false
    private var bag: Set<AnyCancellable> = []

    init() {
        access = OrchestrAccess(link: link, bundle: nil, ownProductIDs: ProProductID.own)
        #if DEBUG
        let env = ProcessInfo.processInfo
        if env.arguments.contains("-tc-pro") || env.environment["TC_DEMO_PRO"] == "1" { forcedPro = true }
        #endif
        access.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        link.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }

    var isPro: Bool { forcedPro || access.isPro }
    var rows: [OrchestrAccess.Row] { access.rows }
    var grantedBy: String? { forcedPro ? "own" : access.grantedBy }

    func isUnlocked(_ guide: StyleGuide) -> Bool { guide.isFree || isPro }
    func isUnlocked(_ tool: TextTool) -> Bool { tool.isFree || isPro }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await loadProducts(launch: true) }
    }

    func product(_ id: String) -> Product? { rows.first { $0.id == id }?.product }

    func loadProducts(launch: Bool = false) async {
        guard loadState != .loading else { return }
        loadState = .loading
        if launch { await access.onLaunch() } else { await access.load() }
        if let sub = product(ProProductID.yearly)?.subscription, sub.introductoryOffer != nil {
            trialEligible = await sub.isEligibleForIntroOffer
        }
        loadState = rows.isEmpty ? .failed("The App Store returned no plans. Check your connection and try again.") : .loaded
        mirror()
    }

    func purchase(_ product: Product) async {
        busy = product.id
        defer { busy = nil }
        do {
            let done = try await access.purchase(product)
            mirror()
            if done { message = isPro ? "Pro is active. Thank you!" : nil }
        } catch {
            message = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        busy = "restore"
        defer { busy = nil }
        await access.restore()
        mirror()
        message = isPro ? "Purchases restored. Pro is active." : "No Pro purchase was found for this Apple Account."
    }

    func refresh() async {
        await access.refreshEntitlement()
        mirror()
    }

    func foreground() async {
        await link.refresh()
        await refresh()
    }

    /// Keeps the extensions' copy of the flag current.
    private func mirror() {
        let pro = isPro
        if SharedVault.load().isPro != pro { SharedVault.update { $0.isPro = pro } }
    }
}

extension Product.SubscriptionPeriod {
    var unitText: String {
        let name: String
        switch unit {
        case .day: name = "day"
        case .week: name = "week"
        case .month: name = "month"
        case .year: name = "year"
        @unknown default: name = "period"
        }
        return value == 1 ? name : "\(value) \(name)s"
    }

    var lengthText: String {
        switch unit {
        case .day: return "\(value)-day"
        case .week: return "\(value * 7)-day"
        case .month: return "\(value)-month"
        case .year: return "\(value)-year"
        @unknown default: return "\(value)-period"
        }
    }
}
