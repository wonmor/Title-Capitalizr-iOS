//
//  IssuesView.swift
//  Title Capitalizr
//
//  Lists spelling and grammar issues with a one-tap fix for each and a
//  "Fix all" action. The user always stays in control.
//

import SwiftUI

struct IssuesView: View {
    let issues: [GrammarIssue]
    let onFix: (GrammarIssue) -> Void
    let onFixAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.m - 4) {
            SectionTitle(issues.count == 1 ? "1 suggestion" : "\(issues.count) suggestions") {
                if issues.count > 1 {
                    TagButton(title: "Fix all", systemImage: "wand.and.stars", filled: true, action: onFixAll)
                }
            }
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: Bauhaus.Space.m - 4) {
                    GlyphTile(systemImage: issue.systemImage, fill: issue.kind == .aiSuggestion ? Bauhaus.Palette.blue : Bauhaus.Palette.yellow, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title).font(Bauhaus.Typo.bodyBold)
                        Text(issue.message).font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    if let fix = issue.preferredReplacement {
                        TagButton(title: fix.count > 18 ? "Fix" : "\u{201C}\(fix)\u{201D}") { onFix(issue) }
                    }
                }
            }
        }
    }
}
