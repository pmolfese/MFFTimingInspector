//
//  FrameInterval.swift
//  MFFTimingCore
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
//  Typed view over "*_frame_intervals.csv" (write_frame_intervals() in
//  example5_psychopy_photocell_drift.py): one row per displayed frame. These
//  files run to hundreds of thousands of rows, so unlike TrialRecord this
//  keeps only fixed numeric fields -- no per-row raw dictionary -- and callers
//  are expected to summarize (long frames, drop counts) rather than display
//  every row.
//

import Foundation

struct FrameInterval: Sendable, Hashable {
    let frameIndex: Int
    let elapsedSeconds: Double
    let psychopyTimeSeconds: Double?
    let packageTimeSeconds: Double?
    let intervalMs: Double
    let expectedFrames: Int
    let estimatedMissedFrames: Int
    let isLongFrame: Bool
}

enum FrameIntervalCSV {
    static func load(from url: URL) throws -> [FrameInterval] {
        let table = try CSVTable.parse(contentsOf: url)
        return table.rows.compactMap { row -> FrameInterval? in
            guard let frameIndex = row["frame_index"].flatMap(Int.init),
                  let elapsed = row["elapsed_s"].flatMap(Double.init),
                  let intervalMs = row["interval_ms"].flatMap(Double.init) else {
                return nil
            }
            return FrameInterval(
                frameIndex: frameIndex,
                elapsedSeconds: elapsed,
                psychopyTimeSeconds: row["psychopy_time_s"].flatMap(Double.init),
                packageTimeSeconds: row["package_time_s"].flatMap(Double.init),
                intervalMs: intervalMs,
                expectedFrames: row["expected_frames"].flatMap(Int.init) ?? 1,
                estimatedMissedFrames: row["estimated_missed_frames"].flatMap(Int.init) ?? 0,
                isLongFrame: row["long_frame"] == "True"
            )
        }
    }

    /// Compact health summary, since displaying 200k+ rows is never the UI's
    /// first move -- only frames worth looking at (long/missed) are.
    static func summarize(_ frames: [FrameInterval]) -> FrameIntervalSummary {
        let longFrames = frames.filter(\.isLongFrame)
        let missedTotal = frames.reduce(0) { $0 + $1.estimatedMissedFrames }
        return FrameIntervalSummary(
            frameCount: frames.count,
            longFrameCount: longFrames.count,
            estimatedMissedFrames: missedTotal,
            longFrames: longFrames
        )
    }
}

struct FrameIntervalSummary: Sendable {
    let frameCount: Int
    let longFrameCount: Int
    let estimatedMissedFrames: Int
    let longFrames: [FrameInterval]
}

/// A long/dropped frame, placed on the same absolute-time axis as the drift
/// timeline, so a residual or slope anomaly can be checked against "did the
/// display just stall right here" -- a dropped frame delays whatever event
/// depended on that flip while the recorded clocks carry on unaffected, which
/// looks identical to clock jitter unless you can see the two side by side.
struct FrameDropEvent: Identifiable, Sendable {
    let id: Int
    let time: Date
    let intervalMs: Double
    let estimatedMissedFrames: Int
}

/// One point of a downsampled frame-interval trace: enough to see the shape
/// of the refresh pattern over time without plotting all of a 200k+ row
/// file, which would be as slow to render as it would be to look at.
struct FrameIntervalPoint: Identifiable, Sendable {
    let id: Int
    let time: Date
    let intervalMs: Double
}

enum FrameDropTimeline {
    /// `anchorPackageTime`/`anchorLocalTime` are the trial CSV's own
    /// `recording_started` row (`Correlator.recordingStartPackageTime` /
    /// `recordingStartLocalTime`) -- the frame-interval CSV's `package_time_s`
    /// shares that same NetStation clock (both come from `ns.getTime()`), so
    /// the same anchor converts it to an absolute `Date`.
    static func events(
        longFrames: [FrameInterval],
        anchorPackageTime: Double,
        anchorLocalTime: Double
    ) -> [FrameDropEvent] {
        longFrames.enumerated().compactMap { offset, frame in
            guard let packageTime = frame.packageTimeSeconds else { return nil }
            let epoch = anchorLocalTime + (packageTime - anchorPackageTime)
            return FrameDropEvent(
                id: offset,
                time: Date(timeIntervalSince1970: epoch),
                intervalMs: frame.intervalMs,
                estimatedMissedFrames: frame.estimatedMissedFrames
            )
        }
    }

    /// Every frame's interval, evenly strided down to at most `maxPoints` --
    /// a trend overview, not a lossless trace. Strides by array position
    /// (visiting only ~`maxPoints` elements total, not scanning all of
    /// `frames`), since a recording's frame rate is close enough to constant
    /// that position and time both advance roughly uniformly.
    static func downsampledIntervals(
        frames: [FrameInterval],
        anchorPackageTime: Double,
        anchorLocalTime: Double,
        maxPoints: Int = 2000
    ) -> [FrameIntervalPoint] {
        guard !frames.isEmpty, maxPoints > 0 else { return [] }
        let stride = max(1, frames.count / maxPoints)
        var points: [FrameIntervalPoint] = []
        points.reserveCapacity(min(frames.count, maxPoints) + 1)
        for index in Swift.stride(from: 0, to: frames.count, by: stride) {
            let frame = frames[index]
            guard let packageTime = frame.packageTimeSeconds else { continue }
            let epoch = anchorLocalTime + (packageTime - anchorPackageTime)
            points.append(FrameIntervalPoint(id: points.count, time: Date(timeIntervalSince1970: epoch), intervalMs: frame.intervalMs))
        }
        return points
    }
}
