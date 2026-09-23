//
//  TimingProjectDocument.swift
//  MFFTimingToolApp
//
//  Compact, versioned plot data. Source records are deliberately excluded:
//  this file contains only numeric values needed to reconstruct the charts.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ContentTab: String, CaseIterable, Identifiable, Sendable {
    case events = "Events"
    case offsetAnalysis = "Offset analysis"
    case drift = "Drift"

    var id: String { rawValue }
}

nonisolated struct TimingProjectSnapshot: Codable, Sendable {
    static let currentFormatVersion = 2

    let v: Int
    /// Shared epoch origin; every point stores only its small offset from it.
    let b: Double
    let tab: Int
    let o: OffsetPlot?
    let d: DriftPlot?
    let f: FramePlots?

    struct OffsetPlot: Codable, Sendable {
        /// Each entry is [seconds from the shared origin, offset ms].
        let p: [[Double]]
    }

    struct DriftPlot: Codable, Sendable {
        /// [relative time, slope, stage, optional residual], [time, kind], and
        /// [session start, optional engagement]. Integer enums travel as JSON
        /// numbers to keep each point an especially compact unkeyed array.
        let p: [[Double]]
        let t: [[Double]]
        let s: [[Double]]
    }

    struct FramePlots: Codable, Sendable {
        /// Drops: [relative time, interval ms, missed]. Intervals: [time, ms].
        let d: [[Double]]
        let i: [[Double]]
    }
}

enum TimingProjectError: LocalizedError {
    case unsupportedVersion(Int)
    case unsupportedSupportBundleVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This project uses format version \(version), but this version of MFF Timing Inspector supports up to version \(TimingProjectSnapshot.currentFormatVersion)."
        case .unsupportedSupportBundleVersion(let version):
            return "This support bundle uses format version \(version), but this version of MFF Timing Inspector supports up to version \(SupportBundleSnapshot.currentFormatVersion)."
        }
    }
}

struct TimingProjectDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let snapshot: TimingProjectSnapshot

    init(snapshot: TimingProjectSnapshot) {
        self.snapshot = snapshot
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        snapshot = try Self.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encode(snapshot))
    }

    static func load(from url: URL) throws -> TimingProjectSnapshot {
        let data = try Data(contentsOf: url)
        if let snapshot = try? decode(data) {
            return snapshot
        }
        return try JSONDecoder().decode(SupportBundleSnapshot.self, from: data).p
    }

    static func save(_ snapshot: TimingProjectSnapshot, to url: URL) throws {
        try encode(snapshot).write(to: url, options: .atomic)
    }

    private static func encode(_ snapshot: TimingProjectSnapshot) throws -> Data {
        // No pretty printing: large plot series should stay as small as JSON
        // permits. Short field names further reduce per-point overhead.
        try JSONEncoder().encode(snapshot)
    }

    private static func decode(_ data: Data) throws -> TimingProjectSnapshot {
        let snapshot = try JSONDecoder().decode(TimingProjectSnapshot.self, from: data)
        guard snapshot.v <= TimingProjectSnapshot.currentFormatVersion else {
            throw TimingProjectError.unsupportedVersion(snapshot.v)
        }
        return snapshot
    }
}
