//
//  DriftAnalysisTests.swift
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

struct DriftAnalysisTests {
    func loadedDiagnostics() throws -> [DiagnosticRecord] {
        let (records, errors) = try PyNetStationLog.load(from: Fixtures.url("netstation_diagnostics.jsonl"))
        #expect(errors.isEmpty)
        return records
    }

    @Test(.enabled(if: Fixtures.exists("netstation_diagnostics.jsonl"))) func detectsBothSessionsInTheFixture() throws {
        let diagnostics = try loadedDiagnostics()
        let timeline = DriftAnalysis.timeline(from: diagnostics)

        #expect(timeline.sessions.count == 2)
        for session in timeline.sessions {
            #expect(session.engagedTime != nil)
            #expect(session.engagedTime! > session.startTime)
        }
    }

    @Test(.enabled(if: Fixtures.exists("netstation_diagnostics.jsonl"))) func firstFitIsAlwaysWarmupStage() throws {
        let diagnostics = try loadedDiagnostics()
        let timeline = DriftAnalysis.timeline(from: diagnostics)

        let firstFits = timeline.slopePoints.filter { point in
            diagnostics.first { $0.date == point.time }?.recordType == "drift_model_engaged"
        }
        #expect(!firstFits.isEmpty)
        #expect(firstFits.allSatisfy { $0.stage == .warmup })
    }

    @Test(.enabled(if: Fixtures.exists("netstation_diagnostics.jsonl"))) func promotedRecordsAreStableStage() throws {
        let diagnostics = try loadedDiagnostics()
        let timeline = DriftAnalysis.timeline(from: diagnostics)

        let promotedTimes = Set(diagnostics.filter { $0.recordType == "drift_model_promoted" }.compactMap(\.date))
        let promotedPoints = timeline.slopePoints.filter { promotedTimes.contains($0.time) }
        #expect(!promotedPoints.isEmpty)
        #expect(promotedPoints.allSatisfy { $0.stage == .stable })
    }

    @Test(.enabled(if: Fixtures.exists("netstation_diagnostics.jsonl"))) func statusHeartbeatsCarryOutstandingErrorButFitsDoNot() throws {
        let diagnostics = try loadedDiagnostics()
        let timeline = DriftAnalysis.timeline(from: diagnostics)

        let statusTimes = Set(diagnostics.filter { $0.recordType == "drift_model_status" }.compactMap(\.date))
        let statusPoints = timeline.slopePoints.filter { statusTimes.contains($0.time) }
        #expect(!statusPoints.isEmpty)
        #expect(statusPoints.allSatisfy { $0.outstandingErrorMs != nil })

        let engagedTimes = Set(diagnostics.filter { $0.recordType == "drift_model_engaged" }.compactMap(\.date))
        let engagedPoints = timeline.slopePoints.filter { engagedTimes.contains($0.time) }
        #expect(engagedPoints.allSatisfy { $0.outstandingErrorMs == nil })
    }

    @Test(.enabled(if: Fixtures.exists("netstation_diagnostics.jsonl"))) func slopePointsAreSortedByTime() throws {
        let diagnostics = try loadedDiagnostics()
        let timeline = DriftAnalysis.timeline(from: diagnostics)
        for (a, b) in zip(timeline.slopePoints, timeline.slopePoints.dropFirst()) {
            #expect(a.time <= b.time)
        }
    }

    @Test(.enabled(if: Fixtures.exists("netstation_diagnostics.jsonl"))) func transitionsExcludeTheHighFrequencyStatusHeartbeat() throws {
        let diagnostics = try loadedDiagnostics()
        let timeline = DriftAnalysis.timeline(from: diagnostics)

        #expect(!timeline.transitions.contains { $0.record.recordType == "drift_model_status" })
        // Fixture has 2 session_start + 2 drift_model_engaged + 2 drift_model_promoted.
        let counted = Dictionary(grouping: timeline.transitions, by: \.kind).mapValues(\.count)
        #expect(counted[.sessionStart] == 2)
        #expect(counted[.engaged] == 2)
        #expect(counted[.promoted] == 2)
    }

    @Test func emptyDiagnosticsProduceAnEmptyTimeline() {
        let timeline = DriftAnalysis.timeline(from: [])
        #expect(timeline.slopePoints.isEmpty)
        #expect(timeline.transitions.isEmpty)
        #expect(timeline.sessions.isEmpty)
    }
}
