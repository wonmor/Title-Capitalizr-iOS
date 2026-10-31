//
//  PaywallView.swift
//  Title Capitalizr
//
//  Title Capitalizr Pro: every price, period and trial comes from StoreKit.
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
                    perk("doc.text", Bauhaus.Palette.blue, "Format whole essays in MLA 9, APA 7 and Chicago")
                    perk("square.and.arrow.up", Bauhaus.Palette.yellow, "Export Word, PDF, RTF and text, or open in Google Docs")
                    perk("books.vertical", Bauhaus.Palette.red, "Sorted Works Cited with hanging indents and citation fixes")
                    perk("doc.on.doc", Bauhaus.Palette.ink, "Full multi-page preview")
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
                Text("The yearly plan renews automatically unless cancelled at least 24 hours before the end of the period. Manage or cancel it in your App Store account settings. Lifetime is a one-time purchase. Title capitalization, grammar and spelling checks stay free.")
                    .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Bauhaus.Space.l)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .bauhausScreen()
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
        .task { if store.products.isEmpty { await store.loadProducts() } }
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
                ForEach(Array(store.products.enumerated()), id: \.element.id) { i, p in
                    planRow(p)
                    if i < store.products.count - 1 { HRule() }
                }
            }
            .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
        }
    }

    private func planRow(_ p: Product) -> some View {
        let isSelected = selected == p.id
        return Button { selected = p.id } label: {
            HStack(spacing: Bauhaus.Space.m - 4) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.id == ProProductID.yearly ? "YEARLY" : "LIFETIME").font(Bauhaus.Typo.button).tracking(1.2)
                    Text(subtitle(p)).font(Bauhaus.Typo.caption).opacity(0.9)
                }
                Spacer()
                Text(p.displayPrice).font(Bauhaus.Typo.title)
            }
            .foregroundStyle(isSelected ? Bauhaus.Palette.ground : Bauhaus.Palette.ink)
            .padding(Bauhaus.Space.m)
            .background(isSelected ? Bauhaus.Palette.blue : Bauhaus.Palette.ground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func subtitle(_ p: Product) -> String {
        if let sub = p.subscription {
            var s = "\(p.displayPrice) per \(sub.subscriptionPeriod.unitText)"
            if store.trialEligible, let offer = sub.introductoryOffer, offer.paymentMode == .freeTrial {
                s = "\(offer.period.lengthText) free trial, then " + s
            }
            return s
        }
        return "One payment, yours to keep"
    }

    private var buyTitle: String {
        guard let p = store.product(selected) else { return "Choose a plan" }
        if p.subscription != nil, store.trialEligible, p.subscription?.introductoryOffer?.paymentMode == .freeTrial {
            return "Start free trial"
        }
        return "Buy for \(p.displayPrice)"
    }
}
