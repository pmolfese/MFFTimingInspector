//
//  MFFTimingToolApp.swift
//  MFFTimingToolApp
//
//  Developed by P. Molfese, Center for Multimodal Neuroimaging (CMN),
//  National Institute of Mental Health (NIMH), National Institutes of Health (NIH).
//  https://cmn.nimh.nih.gov
//
//  This software is a "work of the United States Government" prepared by a federal
//  employee as part of official duties. As such, it is not subject to copyright
//  protection within the United States (17 U.S.C. § 105). International copyrights
//  may apply.
//

import SwiftUI

@main
struct MFFTimingToolApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("MFF Timing Inspector") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 560)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open MFF…") {
                    appState.isImportingMFF = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        // A separate window per inspected source, so you can have the
        // diagnostics log open next to the trial log while checking one
        // against the other.
        WindowGroup("Source", id: "sourceInspector", for: SourceWindowKind.self) { $kind in
            if let kind {
                SourceInspectorView(kind: kind)
                    .environmentObject(appState)
            }
        }
        .windowResizability(.contentSize)
    }
}
