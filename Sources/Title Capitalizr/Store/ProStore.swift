//
//  ProStore.swift
//  Title Capitalizr
//
//  StoreKit 2 for "Title Capitalizr Pro", which unlocks the essay formatter's full
//  preview and every export. Pro is derived from Transaction.currentEntitlements on
//  launch, on every transaction update and when the app returns to the foreground.
//  Title capitalization, grammar and spelling stay free.
//

import Foundation
import StoreKit
import SwiftUI

enum ProProductID {
    static let yearly = "com.johnseong.titlecapitalizr.pro.yearly"
    static let lifetime = "com.johnseong.titlecapitalizr.pro.lifetime"
    static let all = [yearly, lifetime]
}

/// Pure decision for which entitlements unlock Pro (unit tested).
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

@MainActor
final class ProStore: ObservableObject {
    static let shared = ProStore()

    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var isPro = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var trialEligible = false
    @Published private(set) var busy: String?
    @Published var message: String?

    private var updatesTask: Task<Void, Never>?
    private var forcedPro = false

    init() {
        #if DEBUG
        let env = ProcessInfo.processInfo
        if env.arguments.contains("-tc-pro") || env.environment["TC_DEMO_PRO"] == "1" { forcedPro = true; isPro = true }
        #endif
    }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task {
            await refresh()
            await loadProducts()
        }
    }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    func loadProducts() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let loaded = try await Product.products(for: ProProductID.all)
            products = ProProductID.all.compactMap { id in loaded.first { $0.id == id } }
            if let sub = product(ProProductID.yearly)?.subscription, sub.introductoryOffer != nil {
                trialEligible = await sub.isEligibleForIntroOffer
            }
            loadState = products.isEmpty ? .failed("The App Store returned no plans. Check your connection and try again.") : .loaded
        } catch {
            loadState = .failed("Couldn't reach the App Store: \(error.localizedDescription)")
        }
    }

    func purchase(_ product: Product) async {
        busy = product.id
        defer { busy = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let t) = verification else { message = "The App Store couldn't verify this purchase."; return }
                await t.finish()
                await refresh()
                message = isPro ? "Pro is active. Thank you!" : nil
            case .pending:
                message = "Purchase pending approval. Pro unlocks as soon as it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        busy = "restore"
        defer { busy = nil }
        do { try await AppStore.sync() } catch {
            message = "Restore failed: \(error.localizedDescription)"
            return
        }
        await refresh()
        message = isPro ? "Purchases restored. Pro is active." : "No Pro purchase was found for this Apple Account."
    }

    func refresh() async {
        var snapshots: [ProEntitlementPolicy.Snapshot] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            snapshots.append(.init(productID: t.productID, expirationDate: t.expirationDate, revocationDate: t.revocationDate))
        }
        isPro = forcedPro || ProEntitlementPolicy.isPro(snapshots, now: Date())
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
