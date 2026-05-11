//
//  BiffDownloadApp.swift
//  BiffDownload
//
//  Created by Arnold Biffna on 3/28/26.
//

import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

@main
struct BiffDownloadApp: App {
    @State private var keepAliveTimer: Timer?

    init() {
        UIApplication.shared.isIdleTimerDisabled = true

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "BiffDownload",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]

        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                        Task { @MainActor in
                            UIApplication.shared.isIdleTimerDisabled = false
                            UIApplication.shared.isIdleTimerDisabled = true
                        }
                    }
                }
        }
    }
}
