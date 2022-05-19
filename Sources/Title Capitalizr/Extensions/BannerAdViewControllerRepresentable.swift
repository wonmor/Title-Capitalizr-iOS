//
//  BannerAdViewControllerRepresentable.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-18.
//

import SwiftUI
import GoogleMobileAds

final class BannerAd: UIViewControllerRepresentable {
    let adUnitId: String
    
    init(adUnitId: String) {
        self.adUnitId = adUnitId
    }
    
    
    func makeUIViewController(context: Context) -> BannerAdVC {
        return BannerAdVC(adUnitId: adUnitId)
    }

    func updateUIViewController(_ uiViewController: BannerAdVC, context: Context) {
        
    }
}
