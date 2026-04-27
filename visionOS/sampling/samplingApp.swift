//
//  samplingApp.swift
//  sampling
//
//  Created by 伊藤勇哉 on 2026/04/14.
//

import SwiftUI

@main
struct samplingApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .defaultSize(width: 680, height: 820)
        .windowResizability(.contentSize)
    }
}
