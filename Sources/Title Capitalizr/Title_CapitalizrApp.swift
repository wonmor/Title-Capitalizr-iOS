//
//  Title_CapitalizrApp.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import SwiftUI
import AppTrackingTransparency
import GoogleMobileAds

@main
struct Title_CapitalizrApp: App {
    init() {
            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                // User has not indicated their choice for app tracking
                // You may want to show a pop-up explaining why you are collecting their data
                // Toggle any variables to do this here
            } else {
                ATTrackingManager.requestTrackingAuthorization { status in
                    // Whether or not user has opted in initialize GADMobileAds here it will handle the rest
                                                                
                    GADMobileAds.sharedInstance().start(completionHandler: nil)
                }
            }
        }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear(perform: UIApplication.shared.addTapGestureRecognizer)
        }
    }
}

extension UIApplication {
    func addTapGestureRecognizer() {
        guard let window = windows.first else { return }
        let tapGesture = UITapGestureRecognizer(target: window, action: #selector(UIView.endEditing))
        tapGesture.requiresExclusiveTouchType = false
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        window.addGestureRecognizer(tapGesture)
    }
}

extension UIApplication: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true // set to `false` if you don't want to detect tap during other gestures
    }
}
