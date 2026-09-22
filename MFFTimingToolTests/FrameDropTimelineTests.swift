//
//  FrameDropTimelineTests.swift
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

struct FrameDropTimelineTests {
    @Test func convertsPackageTimeToEpochUsingTheSharedAnchor() {
        let anchorPackageTime = 3.0
        let anchorLocalTime = 1_700_000_000.0 // arbitrary epoch reference

        let longFrames = [
            FrameInterval(
                frameIndex: 42, elapsedSeconds: 10, psychopyTimeSeconds: nil,
                packageTimeSeconds: 13.0, // 10s after anchor's package_time
                intervalMs: 25.0, expectedFrames: 2, estimatedMissedFrames: 1, isLongFrame: true
            ),
        ]

        let events = FrameDropTimeline.events(
            longFrames: longFrames,
            anchorPackageTime: anchorPackageTime,
            anchorLocalTime: anchorLocalTime
        )

        #expect(events.count == 1)
        #expect(events[0].time.timeIntervalSince1970 == anchorLocalTime + 10.0)
        #expect(events[0].intervalMs == 25.0)
        #expect(events[0].estimatedMissedFrames == 1)
    }

    @Test func skipsFramesWithoutAPackageTime() {
        let longFrames = [
            FrameInterval(
                frameIndex: 1, elapsedSeconds: 0, psychopyTimeSeconds: 0,
                packageTimeSeconds: nil, // no package_time_s column value
                intervalMs: 20.0, expectedFrames: 1, estimatedMissedFrames: 0, isLongFrame: true
            ),
        ]
        let events = FrameDropTimeline.events(longFrames: longFrames, anchorPackageTime: 0, anchorLocalTime: 0)
        #expect(events.isEmpty)
    }

    @Test(.enabled(if: Fixtures.exists("egi_timing.csv"))) func recordingStartLocalTimeMatchesTheRealFixtureRow() throws {
        let trials = try TrialCSV.load(from: Fixtures.url("egi_timing.csv"))
        let localTime = try #require(Correlator.recordingStartLocalTime(in: trials))
        #expect(abs(localTime - 1789988760.6063838) < 1e-6)
    }
}
