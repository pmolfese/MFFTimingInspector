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
    @Published var mffSourceName: String?
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
    @Published var contentTab: ContentTab = .events

    @Published var isOpeningProject = false
    @Published var isExportingProject = false
    @Published var isExportingSupportBundle = false
    @Published var projectExportDocument: TimingProjectDocument?
    @Published var supportBundleExportDocument: SupportBundleDocument?
    @Published private(set) var diagnosticParseErrors: [String] = []

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
    @Published private(set) var restoredOffsetSummary: OffsetSummary?

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

    /// Frame timing is anchored to the experiment computer's `local_time`,
    /// while a real MFF can carry a stale NetStation calendar date. Offset
    /// plots use the MFF event clock, so translate frame marks by the robust
    /// median difference from already-correlated event/trial pairs. Drift
    /// plots continue using the original local-time frame series because the
    /// diagnostics JSONL shares that clock.
    var frameDropEventsOnMFFClock: [FrameDropEvent] {
        guard let shift = mffClockShiftFromLocalTime else { return [] }
        return frameDropEvents.map {
            FrameDropEvent(
                id: $0.id,
                time: $0.time.addingTimeInterval(shift),
                intervalMs: $0.intervalMs,
                estimatedMissedFrames: $0.estimatedMissedFrames
            )
        }
    }

    var frameIntervalSeriesOnMFFClock: [FrameIntervalPoint] {
        guard let shift = mffClockShiftFromLocalTime else { return [] }
        return frameIntervalSeries.map {
            FrameIntervalPoint(
                id: $0.id,
                time: $0.time.addingTimeInterval(shift),
                intervalMs: $0.intervalMs
            )
        }
    }

    var mffClockShiftFromLocalTime: TimeInterval? {
        Self.mffClockShiftFromLocalTime(in: matchedEvents)
    }

    static func mffClockShiftFromLocalTime(in matches: [MatchedEvent]) -> TimeInterval? {
        let shifts = matches.compactMap { match -> TimeInterval? in
            guard let localTime = match.trial?.localTime else { return nil }
            return match.mffEvent.beginDate.timeIntervalSince1970 - localTime
        }.sorted()
        guard !shifts.isEmpty else { return nil }
        let middle = shifts.count / 2
        if shifts.count.isMultiple(of: 2) {
            return (shifts[middle - 1] + shifts[middle]) / 2
        }
        return shifts[middle]
    }

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
        guard !trials.isEmpty else {
            matchedEvents = mffEvents.map { MatchedEvent(mffEvent: $0, trial: nil, deltaSeconds: nil) }
            return
        }
        matchedEvents = Correlator.matchMFFEvents(mffEvents, toTrials: trials, anchorPackageTime: anchorPackageTime)
    }

    func openMFF(url: URL) {
        do {
            restoredOffsetSummary = nil
            mffEvents = try MFFEventLoader.loadEvents(from: url)
            mffURL = url
            mffSourceName = url.lastPathComponent
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
            diagnosticParseErrors = parseErrors.map(\.localizedDescription)
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

    // MARK: - Project documents

    var suggestedProjectFilename: String {
        guard let source = mffSourceName, !source.isEmpty else { return "Timing Analysis" }
        let base = (source as NSString).deletingPathExtension
        return base.isEmpty ? "Timing Analysis" : "\(base) Timing Analysis"
    }

    func projectSnapshot() -> TimingProjectSnapshot {
        let offsetSummary: OffsetSummary? = restoredOffsetSummary ?? {
            guard !offsetPrimarySelection.isEmpty, !offsetReferenceSelection.isEmpty else { return nil }
            return OffsetAnalysis.computeOffsets(
                events: mffEvents,
                primaryCodes: offsetPrimarySelection,
                referenceCodes: offsetReferenceSelection,
                pairMode: offsetPairMode
            )
        }()

        let timeOrigin = (
            offsetSummary?.pairs.compactMap { $0.referenceEvent == nil ? nil : $0.primaryEvent.beginDate.timeIntervalSince1970 } ?? []
            + driftTimeline.slopePoints.map { $0.time.timeIntervalSince1970 }
            + driftTimeline.transitions.map { $0.time.timeIntervalSince1970 }
            + driftTimeline.sessions.map { $0.startTime.timeIntervalSince1970 }
            + frameDropEvents.map { $0.time.timeIntervalSince1970 }
            + frameIntervalSeries.map { $0.time.timeIntervalSince1970 }
        ).min() ?? 0

        let offsetPlot = offsetSummary.map { summary in
            TimingProjectSnapshot.OffsetPlot(p: summary.pairs.compactMap { pair in
                guard let delta = pair.deltaMilliseconds else { return nil }
                return [pair.primaryEvent.beginDate.timeIntervalSince1970 - timeOrigin, delta]
            })
        }
        let driftPlot: TimingProjectSnapshot.DriftPlot? = driftTimeline.slopePoints.isEmpty ? nil : .init(
            p: driftTimeline.slopePoints.map {
                var values = [$0.time.timeIntervalSince1970 - timeOrigin, $0.slopeMsPerHour, Double(Self.stageNumber($0.stage))]
                if let residual = $0.outstandingErrorMs { values.append(residual) }
                return values
            },
            t: driftTimeline.transitions.map {
                var values = [$0.time.timeIntervalSince1970 - timeOrigin, Double(Self.transitionNumber($0.kind))]
                if let stage = $0.stage { values.append(Double(Self.stageNumber(stage))) }
                return values
            },
            s: driftTimeline.sessions.map {
                var values = [$0.startTime.timeIntervalSince1970 - timeOrigin]
                if let engaged = $0.engagedTime { values.append(engaged.timeIntervalSince1970 - timeOrigin) }
                return values
            }
        )
        let framePlots: TimingProjectSnapshot.FramePlots? = frameDropEvents.isEmpty && frameIntervalSeries.isEmpty ? nil : .init(
            d: frameDropEvents.map {
                [$0.time.timeIntervalSince1970 - timeOrigin, $0.intervalMs, Double($0.estimatedMissedFrames)]
            },
            i: frameIntervalSeries.map {
                [$0.time.timeIntervalSince1970 - timeOrigin, $0.intervalMs]
            }
        )

        return TimingProjectSnapshot(
            v: TimingProjectSnapshot.currentFormatVersion,
            b: timeOrigin,
            tab: Self.tabNumber(contentTab),
            o: offsetPlot,
            d: driftPlot,
            f: framePlots
        )
    }

    var suggestedSupportBundleFilename: String {
        "\(suggestedProjectFilename) Support Bundle"
    }

    func supportBundleSnapshot() -> SupportBundleSnapshot {
        let info = Bundle.main.infoDictionary
        let diagnosticMessageKeys = ["error", "exception", "message", "send_error", "clock_state_error"]
        let diagnosticFieldKeys: Set<String> = [
            "ntp_ip", "model_samples", "model_span", "consecutive_rejections",
            "drift_consecutive_rejections", "drift_warmup",
            "stall_duration", "rejected_during_stall", "samples_collected",
            "samples_expected", "error", "active_slope_ms_per_hour", "elapsed",
            "model_stage", "stable_engaged", "outstanding_level_error_ms"
        ]
        return SupportBundleSnapshot(
            v: SupportBundleSnapshot.currentFormatVersion,
            created: Date().timeIntervalSince1970,
            app: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info?["CFBundleVersion"] as? String ?? "unknown",
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            p: projectSnapshot(),
            src: .init(
                mff: mffSourceName,
                trials: trialSourceName,
                diagnostics: diagnosticsSourceName,
                frames: frameSourceName
            ),
            cfg: .init(
                primary: offsetPrimarySelection.sorted(),
                reference: offsetReferenceSelection.sorted(),
                pairMode: offsetPairMode.rawValue,
                jitterCenter: offsetJitterCenter.rawValue,
                showFrames: offsetShowFrameIntervals,
                timeAxis: offsetTimeAxisMode.rawValue
            ),
            e: mffEvents.map {
                .init(
                    t: $0.beginDate.timeIntervalSince1970,
                    r: $0.relativeBeginTimeMicroseconds,
                    c: $0.code,
                    s: $0.sourceFile
                )
            },
            tr: trials.map {
                .init(
                    p: $0.packageTime,
                    l: $0.localTime,
                    c: $0.eventCode,
                    r: $0.recordType,
                    y: $0.eventType,
                    result: $0.sendResult,
                    error: $0.sendError
                )
            },
            dg: .init(
                records: diagnostics.map { record in
                    let message = diagnosticMessageKeys.lazy
                        .compactMap { record.fields[$0]?.displayString }
                        .first
                    let fields = record.fields.filter { diagnosticFieldKeys.contains($0.key) }
                    return .init(r: record.recordType, t: record.time, f: fields, message: message)
                },
                parseErrors: diagnosticParseErrors
            ),
            fr: frameSummary.map {
                .init(count: $0.frameCount, long: $0.longFrameCount, missed: $0.estimatedMissedFrames)
            },
            warnings: errorMessage.map { [$0] } ?? []
        )
    }

    func prepareProjectExport() {
        projectExportDocument = TimingProjectDocument(snapshot: projectSnapshot())
        isExportingProject = true
    }

    func prepareSupportBundleExport() {
        // Build once in direct response to the command. Previously this lived
        // in ContentView.body and was rebuilt on every SwiftUI reevaluation,
        // repeatedly walking thousands of events before the save panel could
        // appear.
        supportBundleExportDocument = SupportBundleDocument(bundle: supportBundleSnapshot())
        isExportingSupportBundle = true
    }

    func finishExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            errorMessage = nil
        case .failure(let error):
            // Cancellation is reported through this callback too; it is not
            // useful as a persistent red error in the source sidebar.
            if (error as NSError).code != NSUserCancelledError {
                errorMessage = error.localizedDescription
            }
        }
    }

    func finishSupportBundleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            errorMessage = nil
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                errorMessage = "Could not export support bundle: \(error.localizedDescription)"
            }
        }
    }

    func openProject(url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            if let supportBundle = try? SupportBundleDocument.load(from: url) {
                apply(supportBundle)
            } else {
                let snapshot = try TimingProjectDocument.load(from: url)
                apply(snapshot)
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func apply(_ snapshot: TimingProjectSnapshot) {
        // A project is a plot snapshot, not a source archive. Clear all raw
        // records before rebuilding only the derived chart structures.
        mffURL = nil
        mffSourceName = nil
        mffEvents = []
        trialSourceName = nil
        trials = []
        diagnosticsSourceName = nil
        diagnostics = []
        diagnosticParseErrors = []
        frameSourceName = nil
        frames = []
        frameSummary = nil
        selection = nil
        eventCodeFilter = []
        offsetPrimarySelection = []
        offsetReferenceSelection = []
        offsetSelectedPairID = nil
        matchedEvents = []

        contentTab = Self.tab(snapshot.tab)

        if let plot = snapshot.o {
            let pairs = plot.p.enumerated().compactMap { index, point -> OffsetPair? in
                guard point.count >= 2 else { return nil }
                let primary = Self.placeholderEvent(index: index * 2, time: snapshot.b + point[0], code: "Saved")
                let reference = Self.placeholderEvent(
                    index: index * 2 + 1,
                    time: snapshot.b + point[0] + point[1] / 1000,
                    code: "Saved"
                )
                return OffsetPair(id: index, primaryEvent: primary, referenceEvent: reference)
            }
            restoredOffsetSummary = OffsetAnalysis.summarize(pairs)
        } else {
            restoredOffsetSummary = nil
        }

        if let plot = snapshot.d {
            let stages: [DriftStage] = [.unknown, .warmup, .stable]
            let kinds = DriftTransitionKind.allCases
            let points = plot.p.enumerated().compactMap { index, point -> DriftSlopePoint? in
                guard point.count >= 3 else { return nil }
                let stageNumber = Int(point[2])
                return DriftSlopePoint(
                    id: index,
                    time: Date(timeIntervalSince1970: snapshot.b + point[0]),
                    elapsedSeconds: nil,
                    slopeMsPerHour: point[1],
                    stage: stages.indices.contains(stageNumber) ? stages[stageNumber] : .unknown,
                    outstandingErrorMs: point.count > 3 ? point[3] : nil
                )
            }
            let transitions = plot.t.enumerated().compactMap { index, item -> DriftTransition? in
                guard item.count >= 2, kinds.indices.contains(Int(item[1])) else { return nil }
                let kind = kinds[Int(item[1])]
                let epoch = snapshot.b + item[0]
                let record = DiagnosticRecord(index: index, sourceFile: "", recordType: kind.rawValue, time: epoch, fields: [:])
                let stageNumber = item.count > 2 ? Int(item[2]) : -1
                let stage = stages.indices.contains(stageNumber) ? stages[stageNumber] : nil
                return DriftTransition(
                    id: index,
                    time: Date(timeIntervalSince1970: epoch),
                    kind: kind,
                    stage: stage,
                    record: record
                )
            }
            let sessions = plot.s.enumerated().compactMap { index, item -> DriftSession? in
                guard let start = item.first else { return nil }
                return DriftSession(
                    id: index,
                    startTime: Date(timeIntervalSince1970: snapshot.b + start),
                    engagedTime: item.count > 1 ? Date(timeIntervalSince1970: snapshot.b + item[1]) : nil
                )
            }
            driftTimeline = DriftTimeline(slopePoints: points, transitions: transitions, sessions: sessions)
        } else {
            driftTimeline = DriftTimeline(slopePoints: [], transitions: [], sessions: [])
        }

        frameDropEvents = snapshot.f?.d.enumerated().compactMap { index, point -> FrameDropEvent? in
            guard point.count >= 3 else { return nil }
            return FrameDropEvent(
                id: index,
                time: Date(timeIntervalSince1970: snapshot.b + point[0]),
                intervalMs: point[1],
                estimatedMissedFrames: Int(point[2])
            )
        } ?? []
        frameIntervalSeries = snapshot.f?.i.enumerated().compactMap { index, point -> FrameIntervalPoint? in
            guard point.count >= 2 else { return nil }
            return FrameIntervalPoint(id: index, time: Date(timeIntervalSince1970: snapshot.b + point[0]), intervalMs: point[1])
        } ?? []
        offsetShowFrameIntervals = !frameIntervalSeries.isEmpty
        offsetTimeAxisMode = .absolute
    }

    private func apply(_ bundle: SupportBundleSnapshot) {
        apply(bundle.p)
        mffSourceName = bundle.src.mff
        trialSourceName = bundle.src.trials
        diagnosticsSourceName = bundle.src.diagnostics
        frameSourceName = bundle.src.frames

        mffEvents = bundle.e.enumerated().map { index, event in
            MFFEvent(
                index: index + 1,
                sourceFile: event.s,
                beginDate: Date(timeIntervalSince1970: event.t),
                rawBeginTime: "",
                relativeBeginTimeMicroseconds: event.r,
                durationMicroseconds: nil,
                code: event.c,
                label: nil,
                eventDescription: nil,
                sourceDevice: nil,
                keys: [:]
            )
        }
        trials = bundle.tr.enumerated().map { index, trial in
            var fields = ["record_type": trial.r]
            if let value = trial.p { fields["package_time"] = String(value) }
            if let value = trial.l { fields["local_time"] = String(value) }
            if let value = trial.c { fields["event_code"] = value }
            if let value = trial.y { fields["event_type"] = value }
            if let value = trial.result { fields["send_result"] = value }
            if let value = trial.error { fields["send_error"] = value }
            return TrialRecord(index: index + 1, sourceFile: bundle.src.trials ?? "", rawFields: fields)
        }
        diagnostics = bundle.dg.records.enumerated().map { index, record in
            var fields: [String: JSONValue] = record.f ?? [:]
            fields["record"] = .string(record.r)
            if let time = record.t { fields["time"] = .number(time) }
            if let message = record.message { fields["message"] = .string(message) }
            return DiagnosticRecord(
                index: index + 1,
                sourceFile: bundle.src.diagnostics ?? "",
                recordType: record.r,
                time: record.t,
                fields: fields
            )
        }
        diagnosticParseErrors = bundle.dg.parseErrors
        if let frame = bundle.fr {
            frameSummary = FrameIntervalSummary(
                frameCount: frame.count,
                longFrameCount: frame.long,
                estimatedMissedFrames: frame.missed,
                longFrames: []
            )
        }
        offsetPrimarySelection = Set(bundle.cfg.primary)
        offsetReferenceSelection = Set(bundle.cfg.reference)
        offsetPairMode = PairMode(rawValue: bundle.cfg.pairMode) ?? .nearest
        offsetJitterCenter = JitterCenter(rawValue: bundle.cfg.jitterCenter) ?? .median
        offsetShowFrameIntervals = bundle.cfg.showFrames
        offsetTimeAxisMode = TimeAxisMode(rawValue: bundle.cfg.timeAxis) ?? .absolute
        eventCodeFilter = Set(mffEvents.map(\.code))
        recomputeMatchedEvents()
        // Unlike a Lite project, a support bundle contains the original event
        // codes. Recompute from them instead of retaining the plot-only
        // placeholder pairs labeled "Saved".
        restoredOffsetSummary = nil
        // Version 2 retains the small set of diagnostic values needed to
        // rebuild transition details and warmup/stable model stages.
        if bundle.dg.records.contains(where: { $0.f != nil }) {
            driftTimeline = DriftAnalysis.timeline(from: diagnostics)
        }
    }

    private static func placeholderEvent(index: Int, time: Double, code: String) -> MFFEvent {
        MFFEvent(
            index: index,
            sourceFile: "",
            beginDate: Date(timeIntervalSince1970: time),
            rawBeginTime: "",
            relativeBeginTimeMicroseconds: nil,
            durationMicroseconds: nil,
            code: code,
            label: nil,
            eventDescription: nil,
            sourceDevice: nil,
            keys: [:]
        )
    }

    private static func tabNumber(_ tab: ContentTab) -> Int {
        switch tab {
        case .events: return 0
        case .offsetAnalysis: return 1
        case .drift: return 2
        }
    }

    private static func tab(_ number: Int) -> ContentTab {
        switch number {
        case 1: return .offsetAnalysis
        case 2: return .drift
        default: return .events
        }
    }

    private static func stageNumber(_ stage: DriftStage) -> Int {
        switch stage {
        case .unknown: return 0
        case .warmup: return 1
        case .stable: return 2
        }
    }

    private static func transitionNumber(_ kind: DriftTransitionKind) -> Int {
        DriftTransitionKind.allCases.firstIndex(of: kind) ?? 0
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
