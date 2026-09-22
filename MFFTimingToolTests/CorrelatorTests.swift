//
//  CorrelatorTests.swift
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

struct CorrelatorTests {
    func stagedMFF() throws -> URL {
        let eventsFile = Fixtures.url("Events_stm.xml")
        let mffDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathExtension("mff")
        try FileManager.default.createDirectory(at: mffDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: eventsFile, to: mffDirectory.appendingPathComponent("Events_stm.xml"))
        return mffDirectory
    }

    func fixtureTrials() throws -> [TrialRecord] {
        try TrialCSV.load(from: Fixtures.url("egi_timing.csv"))
    }

    @Test(.enabled(if: Fixtures.exists("egi_timing.csv"))) func recordingStartPackageTimeMatchesFixture() throws {
        let trials = try fixtureTrials()
        let anchor = try #require(Correlator.recordingStartPackageTime(in: trials))
        #expect(abs(anchor - 3.2192892000311986) < 1e-9)
    }

    @Test(.enabled(if: Fixtures.exists("Events_stm.xml") && Fixtures.exists("egi_timing.csv")))
    func matchMFFEventsFindsTheSendingTrial() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)
        let trials = try fixtureTrials()
        let anchor = try #require(Correlator.recordingStartPackageTime(in: trials))

        let matches = Correlator.matchMFFEvents(events, toTrials: trials, anchorPackageTime: anchor)
        #expect(matches.count == 4)

        // The first three fixture events were built directly from real CSV
        // rows (trial_index 1-3), so they must match those exact rows.
        #expect(matches[0].trial?.trialIndex == 1)
        #expect(matches[1].trial?.trialIndex == 2)
        #expect(matches[2].trial?.trialIndex == 3)
        for match in matches.prefix(3) {
            #expect(abs(match.deltaSeconds ?? .infinity) < 1e-6)
        }

        // The fourth fixture event was deliberately placed ~1600s past the
        // last real trial, so nothing in the CSV should match it.
        #expect(matches[3].trial == nil)
        #expect(matches[3].deltaSeconds == nil)
    }

    @Test(.enabled(if: Fixtures.exists("egi_timing.csv") && Fixtures.exists("netstation_diagnostics.jsonl")))
    func nearestDiagnosticFindsSessionStartForFirstTrial() throws {
        let trials = try fixtureTrials()
        let (diagnostics, _) = try PyNetStationLog.load(from: Fixtures.url("netstation_diagnostics.jsonl"))

        let firstStim = try #require(trials.first { $0.eventCode == "stm+" })
        let nearest = Correlator.nearestDiagnostic(to: firstStim, in: diagnostics, tolerance: 30)
        #expect(nearest != nil)
        // firstStim.localTime is ~1789988769.9, closest to the second
        // session_start (~1789988756.76) among session_start/display_timing
        // records, all well within a 30s tolerance.
        #expect(abs((nearest?.time ?? 0) - (firstStim.localTime ?? 0)) <= 30)
    }
}
