//
//  ShareViewController.swift
//  Title Capitalizr Share Extension (iOS)
//
//  Share selected text from any app: pick a style guide, see the result, copy it or keep it in
//  History. Free users get Title Case, MLA and APA; Pro (read from the shared vault) gets every guide.
//

import SwiftUI
import TitleCaseKit
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Bauhaus.registerFonts()
        let model = ShareModel()
        let host = UIHostingController(rootView: ShareRoot(model: model, done: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        loadText { text in Task { @MainActor in model.input = text } }
    }

    private func loadText(_ completion: @escaping (String) -> Void) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            p.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                if let s = item as? String { completion(s) }
                else if let d = item as? Data, let s = String(data: d, encoding: .utf8) { completion(s) }
                else if let u = item as? URL, let s = try? String(contentsOf: u, encoding: .utf8) { completion(s) }
            }
        } else if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            p.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                if let u = item as? URL { completion(u.absoluteString) }
            }
        }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    @Published var input = ""
    @Published var guide: StyleGuide
    let snapshot = SharedVault.load()

    init() {
        let g = snapshot.lastGuide
        guide = (g.isFree || snapshot.isPro) ? g : .mla
    }

    var isPro: Bool { snapshot.isPro }

    var output: String {
        let dict = isPro ? snapshot.dictionary : CustomDictionary()
        let g = guide
        return BatchConverter.convert(input.trimmingCharacters(in: .whitespacesAndNewlines), options: BatchOptions(),
                                      transform: { TitleCaseEngine.apply($0, guide: g, dictionary: dict) })
    }

    func save() {
        let out = output
        let g = guide
        let text = input
        SharedVault.update { s in
            if text.contains("\n") { s.pendingInput = text } else { s.record(input: text, output: out, guide: g) }
        }
    }
}

struct ShareRoot: View {
    @ObservedObject var model: ShareModel
    var done: () -> Void
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bauhaus.Space.m) {
                HStack {
                    Text("TITLE CAPITALIZR").font(Bauhaus.Typo.title).tracking(1)
                    Spacer()
                    TagButton(title: "Done", filled: true, action: done)
                }
                HRule(thickness: Bauhaus.Rule.heavy)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 0)], spacing: 0) {
                    ForEach(StyleGuide.allCases) { g in
                        let locked = !(g.isFree || model.isPro)
                        Button { if !locked { model.guide = g } } label: {
                            HStack(spacing: 4) {
                                Text(g.shortName.uppercased()).font(Bauhaus.Typo.button).lineLimit(1).minimumScaleFactor(0.7)
                                if locked { Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)) }
                            }
                            .foregroundStyle(g == model.guide ? Bauhaus.Palette.ground : (locked ? Bauhaus.Palette.inkDisabled : Bauhaus.Palette.ink))
                            .frame(maxWidth: .infinity, minHeight: Bauhaus.tapTarget)
                            .background(g == model.guide ? Bauhaus.Palette.blue : Bauhaus.Palette.ground)
                            .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.thin))
                        }
                        .buttonStyle(.plain)
                        .disabled(locked)
                        .accessibilityLabel(g.displayName + (locked ? ", Pro" : ""))
                    }
                }
                .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
                if !model.isPro {
                    Text("More style guides are part of Title Capitalizr Pro. Open the app to see the plans.")
                        .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                }
                Panel {
                    Text(model.input.isEmpty ? "Waiting for text" : model.output)
                        .font(Bauhaus.Typo.result)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Bauhaus.Space.m)
                }
                HStack(spacing: Bauhaus.Space.s) {
                    BarButton(title: copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", kind: .action) {
                        UIPasteboard.general.string = model.output
                        model.save()
                        copied = true
                    }
                    BarButton(title: "Save to History", systemImage: "clock.arrow.circlepath", kind: .secondary) {
                        model.save()
                        done()
                    }
                }
                .disabled(model.input.isEmpty)
            }
            .padding(Bauhaus.Space.l)
        }
        .bauhausScreen()
    }
}
