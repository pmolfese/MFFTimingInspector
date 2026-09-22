//
//  FrameIntervalCSVTests.swift
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

struct FrameIntervalCSVTests {
    @Test(.enabled(if: Fixtures.exists("frame_intervals_sample.csv"))) func loadAndSummarize() throws {
        let url = Fixtures.url("frame_intervals_sample.csv")
        let frames = try FrameIntervalCSV.load(from: url)
        #expect(frames.count == 2000)
        #expect(frames.first?.frameIndex == 1)

        let summary = FrameIntervalCSV.summarize(frames)
        #expect(summary.frameCount == 2000)
        #expect(summary.longFrameCount == summary.longFrames.count)
        #expect(summary.estimatedMissedFrames >= 0)
    }
}
