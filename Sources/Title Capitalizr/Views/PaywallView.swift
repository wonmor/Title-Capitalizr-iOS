//
//  PaywallView.swift
//  Title Capitalizr
//
//  Title Capitalizr Pro and Orchestr All Access. Order: All Access (annual, monthly), then the
//  app's own plans. Every price, period and trial comes from StoreKit. All Access never shows a
//  trial line.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject var store: ProStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected = ProProductID.yearly

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
                header
                VStack(alignment: .leading, spacing: Bauhaus.Space.m - 4) {
                    ForEach(ProFeature.allCases) { f in
                        perk(f.systemImage, color(for: f), f.title)
                    }
                }
                plans
                if store.isPro {
                    BarButton(title: "Pro is active", systemImage: "checkmark", kind: .action) { dismiss() }
                } else {
                    BarButton(title: buyTitle, systemImage: "lock.open", kind: .pro) {
                        guard let p = store.product(selected) else { return }
                        Task { await store.purchase(p) }
                    }
                    .disabled(store.product(selected) == nil || store.busy != nil)
                    .accessibilityIdentifier("paywall-buy")
                }
                if let m = store.message {
                    Text(m).font(Bauhaus.Typo.body).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Bauhaus.Space.m) {
                    Button("Restore purchases") { Task { await store.restore() } }
                    Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Link("Privacy", destination: URL(string: "https://github.com/wonmor/Title-Capitalizr-iOS/blob/main/PRIVACY.md")!)
                }
                .font(Bauhaus.Typo.font(14, weight: .semibold, relativeTo: .footnote))
                .buttonStyle(.plain)
                .foregroundStyle(Bauhaus.Palette.blue)
                Text("Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Manage or cancel them in your App Store account settings. Lifetime is a one-time purchase. Title case in Title Case, MLA and APA, history and the basic text tools stay free.")
                    .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Bauhaus.Space.l)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .bauhausScreen()
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 680)
        #endif
        .task {
            if store.rows.isEmpty { await store.loadProducts() }
            if store.product(selected) == nil, let first = store.rows.first(where: { $0.kind == .own }) ?? store.rows.first { selected = first.id }
        }
    }

    private func color(for f: ProFeature) -> Color {
        switch f {
        case .guides, .essay: return Bauhaus.Palette.blue
        case .batch, .dictionary: return Bauhaus.Palette.yellow
        case .tools, .shortcuts: return Bauhaus.Palette.ink
        case .ai: return Bauhaus.Palette.red
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("TITLE CAPITALIZR").font(Bauhaus.Typo.section).tracking(2)
                Text("PRO").font(Bauhaus.Typo.font(64, weight: .heavy, relativeTo: .largeTitle)).foregroundStyle(Bauhaus.Palette.red)
                HRule(thickness: Bauhaus.Rule.heavy)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                    .frame(width: Bauhaus.tapTarget, height: Bauhaus.tapTarget)
                    .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
    }

    private func perk(_ glyph: String, _ fill: Color, _ text: String) -> some View {
        HStack(spacing: Bauhaus.Space.m - 4) {
            GlyphTile(systemImage: glyph, fill: fill, size: 32)
            Text(text).font(Bauhaus.Typo.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var plans: some View {
        switch store.loadState {
        case .loading, .idle:
            HStack { ProgressView(); Text("Loading plans").font(Bauhaus.Typo.body) }
        case .failed(let message):
            VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                Text(message).font(Bauhaus.Typo.body)
                TagButton(title: "Try again", systemImage: "arrow.clockwise") { Task { await store.loadProducts() } }
            }
        case .loaded:
            VStack(spacing: 0) {
                ForEach(Array(store.rows.enumerated()), id: \.element.id) { i, row in
                    planRow(row)
                    if i < store.rows.count - 1 { HRule() }
                }
            }
            .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
        }
    }

    private func planRow(_ row: OrchestrAccess.Row) -> some View {
        let isSelected = selected == row.id
        let owned = store.access.ownedProductIDs.contains(row.id)
        return Button { selected = row.id } label: {
            HStack(alignment: .top, spacing: Bauhaus.Space.m - 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 20)
                Image(systemName: row.glyph).font(.system(size: 18, weight: .semibold)).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(row).uppercased()).font(Bauhaus.Typo.button).tracking(1.2)
                    Text(subtitle(row)).font(Bauhaus.Typo.caption).opacity(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Bauhaus.Space.s)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(row.product.displayPrice).font(Bauhaus.Typo.title)
                    if !row.periodText.isEmpty { Text(row.periodText).font(Bauhaus.Typo.caption) }
                }
            }
            .foregroundStyle(isSelected ? Bauhaus.Palette.ground : Bauhaus.Palette.ink)
            .padding(Bauhaus.Space.m)
            .background(isSelected ? Bauhaus.Palette.blue : Bauhaus.Palette.ground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(owned)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(title(row)), \(row.product.displayPrice) \(row.periodText)")
    }

    private func title(_ row: OrchestrAccess.Row) -> String {
        switch row.kind {
        case .allaccess: return row.title + (row.product.subscription?.subscriptionPeriod.unit == .month ? " Monthly" : " Annual")
        case .own, .bundle: return row.id == ProProductID.lifetime ? "Pro Lifetime" : (row.id == ProProductID.yearly ? "Pro Yearly" : row.title)
        }
    }

    private func subtitle(_ row: OrchestrAccess.Row) -> String {
        if row.kind == .allaccess { return row.subtitle ?? "" }
        if let sub = row.product.subscription {
            var s = "Title Capitalizr Pro, \(row.product.displayPrice) per \(sub.subscriptionPeriod.unitText)"
            if store.trialEligible, let offer = sub.introductoryOffer, offer.paymentMode == .freeTrial {
                s = "\(offer.period.lengthText) free trial, then " + s
            }
            return s
        }
        return "Title Capitalizr Pro. One payment, yours to keep."
    }

    private var buyTitle: String {
        guard let row = store.rows.first(where: { $0.id == selected }) else { return "Choose a plan" }
        let p = row.product
        if row.kind == .own, p.subscription != nil, store.trialEligible, p.subscription?.introductoryOffer?.paymentMode == .freeTrial {
            return "Start free trial"
        }
        return "Buy for \(p.displayPrice)"
    }
}
