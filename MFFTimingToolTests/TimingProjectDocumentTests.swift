//
//  TimingProjectDocumentTests.swift
//  MFFTimingToolTests
//

import Foundation
import Testing
@testable import MFFTimingTool

@MainActor
struct TimingProjectDocumentTests {
    private func snapshot() -> TimingProjectSnapshot {
        TimingProjectSnapshot(
            v: TimingProjectSnapshot.currentFormatVersion,
            b: 1_700_000_000,
            tab: 2,
            o: .init(p: [[0, 12.5], [1, 13.25]]),
            d: .init(
                p: [[0, 2.5, 1], [10, 1.75, 2, -0.4]],
                t: [[0, 0], [10, 2]],
                s: [[0, 2]]
            ),
            f: .init(
                d: [[5, 33.4, 1]],
                i: [[0, 6.7], [1, 6.6]]
            )
        )
    }

    @Test func compactNumericJSONRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        try TimingProjectDocument.save(snapshot(), to: url)
        let data = try Data(contentsOf: url)
        let text = try #require(String(data: data, encoding: .utf8))
        let decoded = try TimingProjectDocument.load(from: url)

        #expect(data.count < 300)
        #expect(!text.contains("sourceFile"))
        #expect(!text.contains("rawFields"))
        #expect(decoded.o?.p.count == 2)
        #expect(decoded.d?.p[1][3] == -0.4)
        #expect(decoded.f?.d[0][2] == 1)
    }

    @Test func openingSnapshotRecreatesPlotModelsWithoutRawSources() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try TimingProjectDocument.save(snapshot(), to: url)

        let state = AppState()
        state.openProject(url: url)

        #expect(state.contentTab == .drift)
        #expect(state.mffEvents.isEmpty)
        #expect(state.diagnostics.isEmpty)
        #expect(state.frames.isEmpty)
        #expect(state.restoredOffsetSummary?.matchedCount == 2)
        #expect(state.driftTimeline.slopePoints.count == 2)
        #expect(state.driftTimeline.slopePoints[1].stage == .stable)
        #expect(state.frameDropEvents.first?.estimatedMissedFrames == 1)
        #expect(state.frameIntervalSeries.count == 2)
    }

    @Test func supportBundleIncludesProjectAndRecreatesCorrelationInputs() throws {
        let state = AppState()
        state.mffSourceName = "recording.mff"
        state.mffEvents = [
            MFFEvent(
                index: 1,
                sourceFile: "Events_1.xml",
                beginDate: Date(timeIntervalSince1970: 1_700_000_100),
                rawBeginTime: "",
                relativeBeginTimeMicroseconds: nil,
                durationMicroseconds: nil,
                code: "E010",
                label: nil,
                eventDescription: nil,
                sourceDevice: nil,
                keys: [:]
            ),
            MFFEvent(
                index: 2,
                sourceFile: "Events_DIN2.xml",
                beginDate: Date(timeIntervalSince1970: 1_700_000_100.001),
                rawBeginTime: "",
                relativeBeginTimeMicroseconds: nil,
                durationMicroseconds: nil,
                code: "DIN2",
                label: nil,
                eventDescription: nil,
                sourceDevice: nil,
                keys: [:]
            )
        ]
        state.trialSourceName = "timing.csv"
        state.trials = [
            TrialRecord(
                index: 1,
                sourceFile: "timing.csv",
                rawFields: [
                    "record_type": "egi_event",
                    "event_code": "E010",
                    "package_time": "42.5",
                    "local_time": "1700000100.1",
                    "send_result": "sent"
                ]
            )
        ]
        state.offsetPrimarySelection = ["E010"]
        state.offsetReferenceSelection = ["DIN2"]
        state.diagnosticsSourceName = "diagnostics.jsonl"
        state.diagnostics = [
            DiagnosticRecord(
                index: 1,
                sourceFile: "diagnostics.jsonl",
                recordType: "session_start",
                time: 1_700_000_000,
                fields: ["record": .string("session_start"), "drift_warmup": .bool(false), "ntp_ip": .string("10.0.0.1")]
            ),
            DiagnosticRecord(
                index: 2,
                sourceFile: "diagnostics.jsonl",
                recordType: "drift_model_engaged",
                time: 1_700_000_010,
                fields: [
                    "record": .string("drift_model_engaged"),
                    "active_slope_ms_per_hour": .number(1.25),
                    "model_samples": .number(13),
                    "model_span": .number(181)
                ]
            )
        ]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        try SupportBundleDocument.save(state.supportBundleSnapshot(), to: url)
        let data = try Data(contentsOf: url)
        let text = try #require(String(data: data, encoding: .utf8))
        let decoded = try SupportBundleDocument.load(from: url)

        #expect(decoded.p.v == TimingProjectSnapshot.currentFormatVersion)
        #expect(decoded.src.mff == "recording.mff")
        #expect(decoded.e.first?.c == "E010")
        #expect(decoded.tr.first?.p == 42.5)
        #expect(decoded.dg.records[1].f?["model_samples"]?.doubleValue == 13)
        #expect(!text.contains("rawFields"))
        #expect(!text.contains("rawBeginTime"))

        let reopened = AppState()
        reopened.openProject(url: url)
        #expect(reopened.mffEvents.count == 2)
        #expect(reopened.trials.count == 1)
        #expect(reopened.matchedEvents.first?.trial?.eventCode == "E010")
        #expect(reopened.restoredOffsetSummary == nil)
        let offsets = OffsetAnalysis.computeOffsets(
            events: reopened.mffEvents,
            primaryCodes: reopened.offsetPrimarySelection,
            referenceCodes: reopened.offsetReferenceSelection,
            pairMode: reopened.offsetPairMode
        )
        #expect(offsets.pairs.first?.primaryEvent.code == "E010")
        #expect(offsets.pairs.first?.referenceEvent?.code == "DIN2")
        let engaged = try #require(reopened.driftTimeline.transitions.first { $0.kind == .engaged })
        #expect(engaged.stage == .stable)
        #expect(engaged.record["model_samples"]?.doubleValue == 13)
    }
}
