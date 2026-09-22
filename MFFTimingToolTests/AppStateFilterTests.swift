//
//  AppStateFilterTests.swift
//  MFFTimingToolTests
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

import Testing
import Foundation
@testable import MFFTimingTool

@MainActor
struct AppStateFilterTests {
    func stagedMFF() throws -> URL {
        let eventsFile = Fixtures.url("Events_din.xml")
        let mffDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathExtension("mff")
        try FileManager.default.createDirectory(at: mffDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: eventsFile, to: mffDirectory.appendingPathComponent("Events_din.xml"))
        return mffDirectory
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func openingAnMFFDefaultsTheFilterToEveryCode() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }

        let appState = AppState()
        appState.openMFF(url: mff)

        #expect(appState.eventCodeFilter == Set(appState.uniqueEventCodes))
        #expect(appState.filteredMatchedEvents.count == appState.mffEvents.count)
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func narrowingTheFilterHidesOtherCodes() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }

        let appState = AppState()
        appState.openMFF(url: mff)
        appState.eventCodeFilter = ["DIN1"]

        #expect(appState.filteredMatchedEvents.allSatisfy { $0.mffEvent.code == "DIN1" })
        #expect(appState.filteredMatchedEvents.count == appState.mffEvents.filter { $0.code == "DIN1" }.count)
        // The full event list is untouched by the filter.
        #expect(appState.mffEvents.count > appState.filteredMatchedEvents.count)
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func reopeningAnMFFResetsTheFilterToTheNewCodes() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }

        let appState = AppState()
        appState.openMFF(url: mff)
        appState.eventCodeFilter = ["DIN1"]

        appState.openMFF(url: mff)
        #expect(appState.eventCodeFilter == Set(appState.uniqueEventCodes))
    }
}
