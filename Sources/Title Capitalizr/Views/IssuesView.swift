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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(issues.count == 1 ? "1 suggestion" : "\(issues.count) suggestions", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                if issues.count > 1 {
                    Button("Fix all", action: onFixAll)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: issue.systemImage)
                        .foregroundColor(issue.kind == .aiSuggestion ? .purple : .orange)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title).font(.subheadline).bold()
                        Text(issue.message).font(.footnote).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 4)
                    if let fix = issue.preferredReplacement {
                        Button {
                            onFix(issue)
                        } label: {
                            Text(fix.count > 18 ? "Fix" : "“\(fix)”")
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
        )
    }
}
