//
//  MFFEventTests.swift
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

struct MFFEventTests {
    /// MFFEventLoader expects a directory containing Events*.xml files, so
    /// the fixture is staged into a temporary ".mff" directory per test.
    func stagedMFF() throws -> URL {
        let eventsFile = Fixtures.url("Events_stm.xml")
        let mffDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathExtension("mff")
        try FileManager.default.createDirectory(at: mffDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: eventsFile, to: mffDirectory.appendingPathComponent("Events_stm.xml"))
        return mffDirectory
    }

    @Test(.enabled(if: Fixtures.exists("Events_stm.xml"))) func loadEventsParsesCodeAndRelativeBeginTime() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)

        #expect(events.count == 4)
        #expect(events[0].code == "stm+")
        #expect(events[0].relativeBeginTimeMicroseconds == 9287362)
        #expect(abs((events[0].relativeBeginTimeSeconds ?? -1) - 9.287362) < 1e-6)
        #expect(events[0].keys["TTyp"] == "S")
        #expect(events[0].keys["TFrq"] == "1000")
    }

    @Test(.enabled(if: Fixtures.exists("Events_stm.xml"))) func loadEventsSortsByBeginDate() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)
        for (a, b) in zip(events, events.dropFirst()) {
            #expect(a.beginDate <= b.beginDate)
        }
    }

    @Test func eventFilesThrowsForMissingDirectory() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect {
            try MFFEventLoader.eventFiles(in: missing)
        } throws: { error in
            guard case MFFTimingError.invalidMFF = error else { return false }
            return true
        }
    }

    @Test(.enabled(if: Fixtures.exists("Events_stm.xml"))) func matchNearest() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)
        let target = events[0]
        let candidates = Array(events.dropFirst())
        let matched = MFFEventLoader.match(event: target, candidates: candidates, mode: .nearest)
        #expect(matched?.index == events[1].index)
    }
}
