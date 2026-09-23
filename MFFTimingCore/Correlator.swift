//
//  Correlator.swift
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
//  Links the three sources on their shared clocks:
//
//    MFF <code>/beginTime  <-->  package_time (CSV row, same event_code)
//                                  local_time (CSV row)  <-->  time (JSONL record)
//
//  `package_time` is egi_pynetstation's NTP/drift-corrected NetStation clock.
//  Real MFF v3 event tracks do not necessarily include relativeBeginTime, and
//  their calendar date can reflect the NetStation host rather than the script
//  host. Shared event-code sequences therefore calibrate one offset between
//  the MFF beginTime clock and package_time. `local_time`
//  (CSV) and `time` (JSONL) are both Python's time.time() epoch on the
//  recording machine, so they line up directly without conversion.
//

import Foundation

struct MatchedEvent: Identifiable, Sendable {
    let mffEvent: MFFEvent
    let trial: TrialRecord?
    /// trial.packageTime - the MFF event time projected onto the package-time
    /// clock, in seconds. Near zero for a clean match; large or nil means
    /// something's off -- a missing send, code mismatch, or no calibration.
    let deltaSeconds: Double?

    init(mffEvent: MFFEvent, trial: TrialRecord?, deltaSeconds: Double?) {
        self.mffEvent = mffEvent
        self.trial = trial
        self.deltaSeconds = deltaSeconds
    }

    var id: Int { mffEvent.index }
}

enum Correlator {
    /// The `package_time` of the CSV's own `recording_started` row. This is
    /// the package/local clock anchor used for frame timing, and a legacy
    /// fallback for synthetic MFF fixtures that explicitly carry
    /// relativeBeginTime. It is not assumed to be a real MFF's time origin.
    static func recordingStartPackageTime(in trials: [TrialRecord]) -> Double? {
        trials.first { $0.recordType == "recording_started" }?.packageTime
    }

    /// The `local_time` (Python epoch) of that same `recording_started` row:
    /// the wall-clock moment `package_time == recordingStartPackageTime`, i.e.
    /// the anchor for converting any other row's `package_time` (or a frame
    /// interval's `package_time_s`, which shares this same NetStation clock)
    /// into an absolute `Date`.
    static func recordingStartLocalTime(in trials: [TrialRecord]) -> Double? {
        trials.first { $0.recordType == "recording_started" }?.localTime
    }

    /// Matches each MFF event to the CSV row (`record_type == "egi_event"`)
    /// most likely to have produced it: same event code, closest package_time
    /// after projecting MFF beginTime onto the package-time clock.
    ///
    /// Calibration is inferred from shared codes whose occurrence counts are
    /// equal in both sources. Each code contributes one median offset, then a
    /// median across codes prevents a high-frequency stimulus code from
    /// overwhelming session landmarks. This handles normal MFF v3 tracks that
    /// omit relativeBeginTime and even a stale NetStation calendar date.
    /// The former relativeBeginTime + recording_started calculation remains a
    /// fallback for sparse/synthetic files that lack a calibrating sequence.
    static func matchMFFEvents(
        _ events: [MFFEvent],
        toTrials trials: [TrialRecord],
        anchorPackageTime: Double? = nil,
        tolerance: Double = 0.25
    ) -> [MatchedEvent] {
        let candidates = trials.filter { $0.recordType == "egi_event" && $0.packageTime != nil }
        // Sorted once per code, not scanned linearly per event: with a few
        // thousand events sharing a code, the linear scan this replaced was
        // O(n^2) -- see SortedMatch.swift.
        let byCode = Dictionary(grouping: candidates, by: { $0.eventCode ?? "" })
            .mapValues { $0.sorted { $0.packageTime! < $1.packageTime! } }
        let packageTimeOffset = inferredPackageTimeOffset(events: events, trialsByCode: byCode)

        return events.map { event in
            let targetPackageTime: Double?
            if let packageTimeOffset {
                targetPackageTime = event.beginDate.timeIntervalSinceReferenceDate + packageTimeOffset
            } else if let anchorPackageTime, let relativeSeconds = event.relativeBeginTimeSeconds {
                targetPackageTime = anchorPackageTime + relativeSeconds
            } else {
                targetPackageTime = nil
            }
            guard let targetPackageTime else {
                return MatchedEvent(mffEvent: event, trial: nil, deltaSeconds: nil)
            }
            let sameCode = byCode[event.code] ?? []
            guard let best = SortedMatch.find(in: sameCode, nearestTo: targetPackageTime, mode: .nearest, key: { $0.packageTime! }) else {
                return MatchedEvent(mffEvent: event, trial: nil, deltaSeconds: nil)
            }
            let delta = best.packageTime! - targetPackageTime
            guard abs(delta) <= tolerance else {
                return MatchedEvent(mffEvent: event, trial: nil, deltaSeconds: nil)
            }
            return MatchedEvent(mffEvent: event, trial: best, deltaSeconds: delta)
        }
    }

    private static func inferredPackageTimeOffset(
        events: [MFFEvent],
        trialsByCode: [String: [TrialRecord]]
    ) -> Double? {
        let eventsByCode = Dictionary(grouping: events, by: \.code)
            .mapValues { $0.sorted { $0.beginDate < $1.beginDate } }
        var offsetsByCode: [Double] = []

        for (code, codeEvents) in eventsByCode {
            guard let codeTrials = trialsByCode[code], codeEvents.count == codeTrials.count else { continue }
            let offsets = zip(codeEvents, codeTrials).compactMap { event, trial -> Double? in
                guard let packageTime = trial.packageTime else { return nil }
                return packageTime - event.beginDate.timeIntervalSinceReferenceDate
            }
            if let offset = median(offsets) {
                offsetsByCode.append(offset)
            }
        }

        return median(offsetsByCode)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// The diagnostic record whose `time` is closest to a trial's `local_time`,
    /// e.g. to show "what was the drift model doing when this trial sent".
    static func nearestDiagnostic(
        to trial: TrialRecord,
        in diagnostics: [DiagnosticRecord],
        tolerance: Double = 30
    ) -> DiagnosticRecord? {
        guard let localTime = trial.localTime else { return nil }
        return PyNetStationLog.nearest(to: localTime, in: diagnostics, tolerance: tolerance)
    }
}
