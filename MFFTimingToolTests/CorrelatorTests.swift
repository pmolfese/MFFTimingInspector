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
    private func event(_ index: Int, code: String, seconds: Double) -> MFFEvent {
        MFFEvent(
            index: index,
            sourceFile: "Events.xml",
            beginDate: Date(timeIntervalSinceReferenceDate: 800_000 + seconds),
            rawBeginTime: "",
            relativeBeginTimeMicroseconds: nil,
            durationMicroseconds: 1_000,
            code: code,
            label: code,
            eventDescription: nil,
            sourceDevice: nil,
            keys: [:]
        )
    }

    private func trial(_ index: Int, code: String, packageTime: Double) -> TrialRecord {
        TrialRecord(
            index: index,
            sourceFile: "timing.csv",
            rawFields: [
                "record_type": "egi_event",
                "event_code": code,
                "package_time": String(packageTime),
                "trial_index": String(index),
            ]
        )
    }

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

    @Test func calibratesFromSharedEventsWhenMFFHasNoRelativeTimes() throws {
        // The MFF clock deliberately has an unrelated/stale absolute date.
        // Only elapsed timing and shared event codes agree with package_time.
        let events = [
            event(1, code: "EXPT", seconds: 0),
            event(2, code: "S011", seconds: 19.819),
            event(3, code: "S011", seconds: 20.319),
            event(4, code: "DIN2", seconds: 19.8195),
        ]
        let trials = [
            trial(1, code: "EXPT", packageTime: 2.0052),
            trial(2, code: "S011", packageTime: 21.82432),
            trial(3, code: "S011", packageTime: 22.32428),
            // A sent event missing from the MFF must not disrupt calibration.
            trial(4, code: "MN51", packageTime: 100),
        ]

        let matches = Correlator.matchMFFEvents(events, toTrials: trials)

        #expect(matches[0].trial?.eventCode == "EXPT")
        #expect(matches[1].trial?.trialIndex == 2)
        #expect(matches[2].trial?.trialIndex == 3)
        for match in matches.prefix(3) {
            #expect(abs(match.deltaSeconds ?? .infinity) < 0.001)
        }
        // DIN is an input track, not an outbound egi_event row.
        #expect(matches[3].trial == nil)
    }

    @Test @MainActor func alignsLocalFrameClockToStaleMFFCalendar() throws {
        let mffEvent = event(1, code: "S011", seconds: 20)
        let localEpoch = mffEvent.beginDate.timeIntervalSince1970 + 8 * 24 * 60 * 60
        let row = TrialRecord(
            index: 1,
            sourceFile: "timing.csv",
            rawFields: [
                "record_type": "egi_event",
                "event_code": "S011",
                "package_time": "20",
                "local_time": String(localEpoch)
            ]
        )
        let shift = try #require(AppState.mffClockShiftFromLocalTime(in: [
            MatchedEvent(mffEvent: mffEvent, trial: row, deltaSeconds: 0)
        ]))

        #expect(abs(shift + 8 * 24 * 60 * 60) < 0.001)
        #expect(abs(Date(timeIntervalSince1970: localEpoch).addingTimeInterval(shift).timeIntervalSince(mffEvent.beginDate)) < 0.001)
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
