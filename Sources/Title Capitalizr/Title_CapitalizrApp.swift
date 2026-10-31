//
//  Title_CapitalizrApp.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import SwiftUI

@main
struct Title_CapitalizrApp: App {
    init() {
        Bauhaus.registerFonts()
        Task { @MainActor in ProStore.shared.start() }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .frame(minWidth: 560, idealWidth: 780, minHeight: 700, idealHeight: 900)
        }
        .defaultSize(width: 780, height: 900)
        Settings {
            SettingsView(store: ProStore.shared)
                .frame(width: 480, height: 640)
        }
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
