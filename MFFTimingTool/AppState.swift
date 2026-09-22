//
//  AppState.swift
//  MFFTimingToolApp
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

import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var mffURL: URL?
    @Published var mffEvents: [MFFEvent] = []

    @Published var trialSourceName: String?
    @Published var trials: [TrialRecord] = []

    @Published var diagnosticsSourceName: String?
    @Published var diagnostics: [DiagnosticRecord] = []

    @Published var frameSourceName: String?
    @Published var frames: [FrameInterval] = []
    @Published var frameSummary: FrameIntervalSummary?

    @Published var selection: Int?
    @Published var errorMessage: String?

    @Published var isImportingMFF = false
    @Published var isImportingTrialCSV = false
    @Published var isImportingDiagnostics = false
    @Published var isImportingFrameIntervals = false

    // Offset analysis view state lives here, not as @State in the view
    // itself, so switching to the Events tab and back doesn't reset it --
    // SwiftUI discards a conditionally-shown view's own @State when it's
    // removed from the tree, but this object stays alive for the session.
    @Published var offsetPrimarySelection: Set<String> = []
    @Published var offsetReferenceSelection: Set<String> = []
    @Published var offsetPairMode: PairMode = .nearest
    @Published var offsetJitterCenter: JitterCenter = .median
    @Published var offsetSelectedPairID: Int?
    @Published var offsetShowFrameIntervals = false
    @Published var offsetTimeAxisMode: TimeAxisMode = .absolute

    /// Codes currently shown in the Events table. Defaults to "every code",
    /// reset whenever a new MFF loads so newly-seen codes aren't hidden.
    @Published var eventCodeFilter: Set<String> = []

    /// The CSV's own `recording_started` row's `package_time`: the origin
    /// `relativeBeginTime` in the MFF is measured from. Nil until a trial CSV
    /// with that row has been imported.
    var anchorPackageTime: Double? {
        Correlator.recordingStartPackageTime(in: trials)
    }

    /// Wall-clock moment the MFF recording actually started (relativeBeginTime
    /// == 0), for charts that offer "time since start of recording" as an
    /// alternative to absolute clock time.
    var recordingStartDate: Date? {
        Correlator.recordingStartLocalTime(in: trials).map { Date(timeIntervalSince1970: $0) }
    }

    /// Every MFF event, matched against the trial CSV (if loaded) via
    /// `Correlator.matchMFFEvents`. Falls back to unmatched rows so the table
    /// is still useful with only an MFF loaded.
    ///
    /// Cached and recomputed only by `recomputeMatchedEvents()`, not on every
    /// access: this used to be a computed property, which meant every
    /// SwiftUI body re-evaluation (e.g. clicking a row just to change
    /// `selection`) reran the full correlation from scratch. Even after
    /// fixing the O(n^2) matcher underneath it, recomputing a few thousand
    /// entries on every render is wasted work a click shouldn't pay for.
    @Published private(set) var matchedEvents: [MatchedEvent] = []

    var uniqueEventCodes: [String] {
        Array(Set(mffEvents.map(\.code))).sorted()
    }

    /// `matchedEvents` restricted to codes currently in `eventCodeFilter` --
    /// what the Events table actually displays.
    var filteredMatchedEvents: [MatchedEvent] {
        matchedEvents.filter { eventCodeFilter.contains($0.mffEvent.code) }
    }

    var selectedMatch: MatchedEvent? {
        guard let selection else { return nil }
        return matchedEvents.first { $0.id == selection }
    }

    var nearestDiagnosticForSelection: DiagnosticRecord? {
        guard let trial = selectedMatch?.trial, !diagnostics.isEmpty else { return nil }
        return Correlator.nearestDiagnostic(to: trial, in: diagnostics)
    }

    /// Clock-drift slope trace, session boundaries, and state transitions
    /// derived from the imported diagnostics log, for the Drift tab. Cached
    /// like `matchedEvents`, for the same reason.
    @Published private(set) var driftTimeline = DriftTimeline(slopePoints: [], transitions: [], sessions: [])

    /// Long/dropped frames placed on the same absolute-time axis as
    /// `driftTimeline`, so a residual or slope anomaly can be checked
    /// against a display stall. Needs both the frame-interval CSV and the
    /// trial CSV (for the epoch anchor), so it's recomputed whenever either
    /// changes -- and, like `matchedEvents`, cached rather than derived on
    /// every access since a full recording can have hundreds of thousands of
    /// frame rows.
    @Published private(set) var frameDropEvents: [FrameDropEvent] = []

    /// Every frame's interval, downsampled -- for the Offset Analysis tab's
    /// optional "show frame intervals" overlay. Computed alongside
    /// `frameDropEvents` (same anchor, same trigger conditions) but kept
    /// separate since it's opt-in and not every caller wants it built.
    @Published private(set) var frameIntervalSeries: [FrameIntervalPoint] = []

    private func recomputeFrameDropEvents() {
        guard let summary = frameSummary,
              let anchorTime = anchorPackageTime,
              let anchorLocal = Correlator.recordingStartLocalTime(in: trials) else {
            frameDropEvents = []
            frameIntervalSeries = []
            return
        }
        frameDropEvents = FrameDropTimeline.events(
            longFrames: summary.longFrames,
            anchorPackageTime: anchorTime,
            anchorLocalTime: anchorLocal
        )
        frameIntervalSeries = FrameDropTimeline.downsampledIntervals(
            frames: frames,
            anchorPackageTime: anchorTime,
            anchorLocalTime: anchorLocal
        )
    }

    private func recomputeMatchedEvents() {
        guard !mffEvents.isEmpty else {
            matchedEvents = []
            return
        }
        guard let anchor = anchorPackageTime else {
            matchedEvents = mffEvents.map { MatchedEvent(mffEvent: $0, trial: nil, deltaSeconds: nil) }
            return
        }
        matchedEvents = Correlator.matchMFFEvents(mffEvents, toTrials: trials, anchorPackageTime: anchor)
    }

    func openMFF(url: URL) {
        do {
            mffEvents = try MFFEventLoader.loadEvents(from: url)
            mffURL = url
            eventCodeFilter = Set(mffEvents.map(\.code))
            errorMessage = nil
            recomputeMatchedEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importTrialCSV(url: URL) {
        do {
            trials = try TrialCSV.load(from: url)
            trialSourceName = url.lastPathComponent
            errorMessage = nil
            recomputeMatchedEvents()
            recomputeFrameDropEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importDiagnostics(url: URL) {
        do {
            let (records, parseErrors) = try PyNetStationLog.load(from: url)
            diagnostics = records
            diagnosticsSourceName = url.lastPathComponent
            errorMessage = parseErrors.first?.localizedDescription
            driftTimeline = DriftAnalysis.timeline(from: records)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFrameIntervals(url: URL) {
        do {
            let loaded = try FrameIntervalCSV.load(from: url)
            frames = loaded
            frameSummary = FrameIntervalCSV.summarize(loaded)
            frameSourceName = url.lastPathComponent
            errorMessage = nil
            recomputeFrameDropEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sorts one or more dropped/opened files or folders into the right slot
    /// by inspecting each one (a folder is an MFF, a .jsonl is the
    /// diagnostics log, a .csv is told apart by its header row) rather than
    /// requiring the source list button that matches. Unrecognized items are
    /// reported, not silently dropped.
    func importDroppedURLs(_ urls: [URL]) {
        var unrecognized: [String] = []

        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            switch SourceClassifier.classify(url) {
            case .mff:
                openMFF(url: url)
            case .diagnosticsJSONL:
                importDiagnostics(url: url)
            case .trialCSV:
                importTrialCSV(url: url)
            case .frameIntervalCSV:
                importFrameIntervals(url: url)
            case .unknown:
                unrecognized.append(url.lastPathComponent)
            }
        }

        if !unrecognized.isEmpty {
            errorMessage = "Didn't recognize: " + unrecognized.joined(separator: ", ")
        }
    }
}
