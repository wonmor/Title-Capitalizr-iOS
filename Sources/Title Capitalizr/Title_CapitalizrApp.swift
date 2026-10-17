//
//  Title_CapitalizrApp.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import SwiftUI

@main
struct Title_CapitalizrApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .frame(minWidth: 520, idealWidth: 600, minHeight: 700, idealHeight: 820)
        }
        .defaultSize(width: 600, height: 820)
        Settings {
            SettingsView()
                .frame(width: 460)
        }
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
