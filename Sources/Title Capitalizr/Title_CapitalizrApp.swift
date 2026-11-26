//
//  Title_CapitalizrApp.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import SwiftUI
import TitleCaseKit

@main
struct Title_CapitalizrApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    #endif

    init() {
        Bauhaus.registerFonts()
        Task { @MainActor in ProStore.shared.start() }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .frame(minWidth: 820, idealWidth: 1180, minHeight: 640, idealHeight: 860)
        }
        .defaultSize(width: 1180, height: 860)
        .commands { EditorCommands() }
        Settings {
            SettingsView(store: ProStore.shared)
                .frame(width: 520, height: 720)
        }
        #else
        WindowGroup {
            ContentView()
        }
        .commands { EditorCommands() }
        #endif
    }
}

/// Menu bar (Mac) and hardware keyboard (iPad, iPhone) commands for the focused window.
struct EditorCommands: Commands {
    @FocusedObject private var model: EditorModel?

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Paste and Convert") { model?.pasteAndConvert() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(model == nil)
        }
        CommandMenu("Convert") {
            Button("Copy Result") { model?.copyResult() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model?.hasInput != true)
            Button("Add to Favourites") { model?.toggleFavorite() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(model?.hasInput != true)
            Button("Clear") { model?.clear() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(model == nil)
            Divider()
            Button("Previous Style Guide") { model?.stepGuide(-1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(model == nil)
            Button("Next Style Guide") { model?.stepGuide(1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(model == nil)
            Divider()
            ForEach(Workspace.allCases) { w in
                Button(w.name) { model?.workspace = w }
                    .keyboardShortcut(w.shortcutKey, modifiers: .command)
                    .disabled(model == nil)
            }
            Divider()
            Button("History") { model?.showingHistory = true }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(model == nil)
            Button("Title Capitalizr Pro") { model?.showingPaywall = true }
                .disabled(model == nil)
        }
    }
}

#if os(macOS)
import AppKit

extension Notification.Name {
    static let tcReceiveText = Notification.Name("tcReceiveText")
}

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let services = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        #if DEBUG
        scheduleSnapshotIfRequested()
        #endif
    }

    #if DEBUG
    /// Screenshot runs only: TC_SNAPSHOT=/path.png renders the main window's content (no title bar)
    /// after TC_SNAPSHOT_DELAY seconds, at TC_SNAPSHOT_SIZE (e.g. 1440x900 points), then quits.
    private func scheduleSnapshotIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["TC_SNAPSHOT"] else { return }
        let delay = Double(env["TC_SNAPSHOT_DELAY"] ?? "4") ?? 4
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let size = env["TC_SNAPSHOT_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2,
               let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                w.setContentSize(NSSize(width: size[0], height: size[1]))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }), let view = w.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
            w.makeFirstResponder(nil)
            view.display()
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
    #endif
}

/// Services menu: "Title Case with Title Capitalizr" (Pro, replaces the selection in place) and
/// "Open in Title Capitalizr" (free, sends the selection to the app).
final class ServiceProvider: NSObject {
    @objc func titleCaseService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "Select some text first." as NSString
            return
        }
        MainActor.assumeIsolated {
            let store = ProStore.shared
            guard store.isPro else {
                error.pointee = "Title case in the Services menu is part of Title Capitalizr Pro." as NSString
                NSApp.activate(ignoringOtherApps: true)
                store.paywallRequested = true
                return
            }
            let library = LibraryStore.shared
            let guide = library.snapshot.lastGuide
            let out = BatchConverter.convert(text, options: BatchOptions(), transform: {
                TitleCaseEngine.apply($0, guide: guide, dictionary: library.dictionary)
            })
            pboard.clearContents()
            pboard.setString(out, forType: .string)
            if !text.contains("\n") { library.record(input: text, output: out, guide: guide) }
        }
    }

    @objc func openService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .tcReceiveText, object: text)
    }
}
#endif
