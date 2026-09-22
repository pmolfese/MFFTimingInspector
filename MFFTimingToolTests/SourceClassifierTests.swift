//
//  SourceClassifierTests.swift
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

struct SourceClassifierTests {
    @Test func classifiesMFFFolderByExtension() throws {
        let mffDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathExtension("mff")
        try FileManager.default.createDirectory(at: mffDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mffDirectory) }

        #expect(SourceClassifier.classify(mffDirectory) == .mff)
    }

    @Test func classifiesRecordingFolderWithoutExtensionByContents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent("Events_ECI.xml"))

        #expect(SourceClassifier.classify(directory) == .mff)
    }

    @Test func classifiesUnrelatedFolderAsUnknown() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(SourceClassifier.classify(directory) == .unknown)
    }

    @Test(.enabled(if: Fixtures.exists("netstation_diagnostics.jsonl"))) func classifiesJSONLByExtension() throws {
        #expect(SourceClassifier.classify(Fixtures.url("netstation_diagnostics.jsonl")) == .diagnosticsJSONL)
    }

    @Test(.enabled(if: Fixtures.exists("egi_timing.csv"))) func classifiesTrialCSVByHeader() throws {
        #expect(SourceClassifier.classify(Fixtures.url("egi_timing.csv")) == .trialCSV)
    }

    @Test(.enabled(if: Fixtures.exists("frame_intervals_sample.csv"))) func classifiesFrameIntervalCSVByHeader() throws {
        #expect(SourceClassifier.classify(Fixtures.url("frame_intervals_sample.csv")) == .frameIntervalCSV)
    }

    @Test func classifiesUnrecognizedCSVAsUnknown() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("csv")
        try "foo,bar,baz\n1,2,3\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(SourceClassifier.classify(url) == .unknown)
    }

    @Test func classifiesMissingFileAsUnknown() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(SourceClassifier.classify(missing) == .unknown)
    }
}
