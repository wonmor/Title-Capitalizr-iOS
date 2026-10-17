//
//  Platform.swift
//  Title Capitalizr
//
//  Small helpers that differ between iOS and macOS.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Platform {
    static func copyToClipboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
}

extension View {
    func hideKeyboard() {
        #if os(iOS)
        let resign = #selector(UIResponder.resignFirstResponder)
        UIApplication.shared.sendAction(resign, to: nil, from: nil, for: nil)
        #endif
    }
}

/// Keys for the user's preferences.
enum SettingsKeys {
    static let aiFeaturesEnabled = "aiFeaturesEnabled"
    static let alternativesEnabled = "alternativesEnabled"
    static let grammarChecksEnabled = "grammarChecksEnabled"
    static let spellingChecksEnabled = "spellingChecksEnabled"
}
