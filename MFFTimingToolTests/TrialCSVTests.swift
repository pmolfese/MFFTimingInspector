//
//  TrialCSVTests.swift
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

struct TrialCSVTests {
    var fixtureURL: URL { Fixtures.url("egi_timing.csv") }

    @Test(.enabled(if: Fixtures.exists("egi_timing.csv"))) func loadParsesKnownColumns() throws {
        let trials = try TrialCSV.load(from: fixtureURL)
        #expect(trials.count == 3013) // 3014 data rows minus the header

        let stimRows = trials.filter { $0.recordType == "egi_event" && $0.eventCode == "stm+" }
        #expect(stimRows.count == 3000)

        let first = try #require(stimRows.first)
        #expect(first.intendedTrigger == "S011")
        #expect(first.blockNum == 1)
        #expect(first.trialIndex == 1)
        #expect(first.stimType == "S")
        #expect(first.toneFreq == 1000.0)
        #expect(abs((first.packageTime ?? -1) - 12.506651400006376) < 1e-9)
        #expect(first.sendResult == "sent")
        #expect(!first.isSendFailure)
    }

    @Test(.enabled(if: Fixtures.exists("egi_timing.csv"))) func recordingStartedRowHasPackageTimeButNoEventCode() throws {
        let trials = try TrialCSV.load(from: fixtureURL)
        let started = try #require(trials.first { $0.recordType == "recording_started" })
        #expect(started.eventCode == nil)
        #expect(abs((started.packageTime ?? -1) - 3.2192892000311986) < 1e-9)
        #expect(abs((started.localTime ?? -1) - 1789988760.6063838) < 1e-6)
    }

    @Test(.enabled(if: Fixtures.exists("egi_timing.csv"))) func unmodeledColumnsRemainInRawFields() throws {
        let trials = try TrialCSV.load(from: fixtureURL)
        let first = try #require(trials.first { $0.eventCode == "stm+" })
        // "capture_time" is modeled; spot-check a raw lookup matches the typed one.
        #expect(first.rawFields["capture_time"] == "617581.3400162")
    }
}
