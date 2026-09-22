//
//  PyNetStationLogTests.swift
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

struct PyNetStationLogTests {
    var fixtureURL: URL { Fixtures.url("netstation_diagnostics.jsonl") }

    @Test(.enabled(if: Fixtures.exists("netstation_diagnostics.jsonl"))) func loadParsesAllRecordTypes() throws {
        let (records, errors) = try PyNetStationLog.load(from: fixtureURL)
        #expect(errors.isEmpty)
        #expect(records.count == 33)

        let types = Set(records.map(\.recordType))
        #expect(types.contains("session_start"))
        #expect(types.contains("display_timing"))
        #expect(types.contains("drift_model_engaged"))
        #expect(types.contains("drift_model_promoted"))
        #expect(types.contains("drift_model_status"))
    }

    @Test(.enabled(if: Fixtures.exists("netstation_diagnostics.jsonl"))) func knownAndUnknownFieldsAreBothAccessible() throws {
        let (records, _) = try PyNetStationLog.load(from: fixtureURL)
        let sessionStart = try #require(records.first { $0.recordType == "session_start" })

        #expect(sessionStart["ntp_ip"]?.stringValue == "10.10.10.51")
        #expect(sessionStart["drift_correction"]?.boolValue == true)
        // "clocks" is a nested object this decoder was never told about --
        // proving the schema-tolerant path handles a record type it doesn't
        // special-case.
        #expect(sessionStart["clocks"]?.objectValue?["platform"]?.stringValue == "win32")
    }

    @Test(.enabled(if: Fixtures.exists("netstation_diagnostics.jsonl"))) func dateDerivesFromEpochTime() throws {
        let (records, _) = try PyNetStationLog.load(from: fixtureURL)
        let first = try #require(records.first)
        let date = try #require(first.date)
        #expect(abs(date.timeIntervalSince1970 - 1789986808.6908321) < 0.001)
    }

    @Test(.enabled(if: Fixtures.exists("netstation_diagnostics.jsonl"))) func nearestFindsClosestRecordWithinTolerance() throws {
        let (records, _) = try PyNetStationLog.load(from: fixtureURL)
        // session 2's session_start is at time 1789988756.760548 (line 18).
        let nearby = PyNetStationLog.nearest(to: 1789988757.0, in: records, tolerance: 5)
        #expect(nearby?.recordType == "session_start")
        #expect(abs((nearby?.time ?? 0) - 1789988756.760548) < 0.001)

        let tooFar = PyNetStationLog.nearest(to: 0, in: records, tolerance: 1)
        #expect(tooFar == nil)
    }
}
