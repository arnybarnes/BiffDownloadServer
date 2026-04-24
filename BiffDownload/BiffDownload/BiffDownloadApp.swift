//
//  BiffDownloadApp.swift
//  BiffDownload
//
//  Created by Arnold Biffna on 3/28/26.
//

import SwiftUI
import UIKit

@main
struct BiffDownloadApp: App {
    init() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
