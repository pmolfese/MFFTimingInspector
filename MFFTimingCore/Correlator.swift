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
//    MFF <code>/relativeBeginTime  <-->  package_time (CSV row, same event_code)
//                                        local_time (CSV row)  <-->  time (JSONL record)
//
//  `package_time` is egi_pynetstation's NTP/drift-corrected NetStation clock --
//  the same clock whose value becomes the MFF event's beginTime -- so it is
//  the anchor between an MFF event and the CSV row that sent it. `local_time`
//  (CSV) and `time` (JSONL) are both Python's time.time() epoch on the
//  recording machine, so they line up directly without conversion.
//

import Foundation

struct MatchedEvent: Identifiable, Sendable {
    let mffEvent: MFFEvent
    let trial: TrialRecord?
    /// trial.packageTime - (anchor + mffEvent.relativeBeginTimeSeconds), in
    /// seconds. Near zero for a clean match; large or nil means something's
    /// off -- a missing send, a code mismatch, or a stale anchor.
    let deltaSeconds: Double?

    init(mffEvent: MFFEvent, trial: TrialRecord?, deltaSeconds: Double?) {
        self.mffEvent = mffEvent
        self.trial = trial
        self.deltaSeconds = deltaSeconds
    }

    var id: Int { mffEvent.index }
}

enum Correlator {
    /// The `package_time` of the CSV's own `recording_started` row: the
    /// origin that `relativeBeginTime` in the MFF is measured from.
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
    /// to the event's relativeBeginTime projected through `anchorPackageTime`.
    static func matchMFFEvents(
        _ events: [MFFEvent],
        toTrials trials: [TrialRecord],
        anchorPackageTime: Double,
        tolerance: Double = 0.25
    ) -> [MatchedEvent] {
        let candidates = trials.filter { $0.recordType == "egi_event" && $0.packageTime != nil }
        // Sorted once per code, not scanned linearly per event: with a few
        // thousand events sharing a code, the linear scan this replaced was
        // O(n^2) -- see SortedMatch.swift.
        let byCode = Dictionary(grouping: candidates, by: { $0.eventCode ?? "" })
            .mapValues { $0.sorted { $0.packageTime! < $1.packageTime! } }

        return events.map { event in
            guard let relativeSeconds = event.relativeBeginTimeSeconds else {
                return MatchedEvent(mffEvent: event, trial: nil, deltaSeconds: nil)
            }
            let targetPackageTime = anchorPackageTime + relativeSeconds
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
