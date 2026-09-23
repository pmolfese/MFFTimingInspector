//
//  DriftAnalysis.swift
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
//  Turns the raw netstation diagnostics JSONL into a shape a "how stable was
//  the clock" view can plot directly: a slope trace with each point staged
//  (nothing has been fit yet / still warming up / stable), the sessions the
//  recording actually ran across (a JSONL can hold more than one -- the
//  script gets re-run, or a session drops and reconnects), and every
//  state-transition worth marking on a timeline.
//

import Foundation

enum DriftStage: String, Sendable, Hashable {
    case warmup
    case stable
    case unknown

    var label: String {
        switch self {
        case .warmup: return "Warmup model"
        case .stable: return "Main model (stable)"
        case .unknown: return "Unknown stage"
        }
    }
}

/// One drift-model fit or status heartbeat with a numeric slope, i.e. every
/// `drift_model_engaged` / `drift_model_status` / `drift_model_promoted`
/// record that actually carries `active_slope_ms_per_hour`.
struct DriftSlopePoint: Identifiable, Sendable {
    let id: Int
    let time: Date
    let elapsedSeconds: Double?
    let slopeMsPerHour: Double
    let stage: DriftStage
    /// ms, present only on `drift_model_status` heartbeats.
    let outstandingErrorMs: Double?
}

enum DriftTransitionKind: String, Sendable, CaseIterable {
    case sessionStart = "session_start"
    case engaged = "drift_model_engaged"
    case promoted = "drift_model_promoted"
    case stalled = "drift_model_stalled"
    case recovered = "drift_model_recovered"
    case undersampled = "drift_undersampled"
    case eventSendFailure = "event_send_failure"

    var label: String {
        switch self {
        case .sessionStart: return "Session start"
        case .engaged: return "Engaged"
        case .promoted: return "Promoted to stable"
        case .stalled: return "Stalled"
        case .recovered: return "Recovered"
        case .undersampled: return "NTP undersampled"
        case .eventSendFailure: return "Event send failure"
        }
    }
}

struct DriftTransition: Identifiable, Sendable {
    let id: Int
    let time: Date
    let kind: DriftTransitionKind
    let stage: DriftStage?
    let record: DiagnosticRecord
}

/// One `connect()`-to-disconnect span, delimited by `session_start` records.
/// `engagedTime` is nil if the model never produced an accepted fit in this
/// session -- the whole span is "not yet engaged", not just its start.
struct DriftSession: Identifiable, Sendable {
    let id: Int
    let startTime: Date
    var engagedTime: Date?
}

struct DriftTimeline: Sendable {
    let slopePoints: [DriftSlopePoint]
    let transitions: [DriftTransition]
    let sessions: [DriftSession]
}

enum DriftAnalysis {
    static func timeline(from diagnostics: [DiagnosticRecord]) -> DriftTimeline {
        let sorted = diagnostics
            .filter { $0.time != nil }
            .sorted { $0.time! < $1.time! }

        var slopePoints: [DriftSlopePoint] = []
        var transitions: [DriftTransition] = []
        var sessions: [DriftSession] = []
        var sessionUsesWarmup: Bool?

        for record in sorted {
            guard let date = record.date else { continue }

            if record.recordType == DriftTransitionKind.sessionStart.rawValue {
                sessionUsesWarmup = record["drift_warmup"]?.boolValue
            }

            let defaultEngagedStage: DriftStage = sessionUsesWarmup == false ? .stable : .warmup
            let recordStage = stage(of: record, defaultEngagedStage: defaultEngagedStage)

            if let kind = DriftTransitionKind(rawValue: record.recordType) {
                let transitionStage: DriftStage?
                switch kind {
                case .engaged: transitionStage = recordStage
                case .promoted: transitionStage = .stable
                default: transitionStage = nil
                }
                transitions.append(
                    DriftTransition(
                        id: transitions.count,
                        time: date,
                        kind: kind,
                        stage: transitionStage,
                        record: record
                    )
                )
            }

            switch record.recordType {
            case DriftTransitionKind.sessionStart.rawValue:
                sessions.append(DriftSession(id: sessions.count, startTime: date, engagedTime: nil))

            case DriftTransitionKind.engaged.rawValue, "drift_model_status", DriftTransitionKind.promoted.rawValue:
                if let slope = record["active_slope_ms_per_hour"]?.doubleValue {
                    slopePoints.append(
                        DriftSlopePoint(
                            id: slopePoints.count,
                            time: date,
                            elapsedSeconds: record["elapsed"]?.doubleValue,
                            slopeMsPerHour: slope,
                            stage: recordStage,
                            outstandingErrorMs: record["outstanding_level_error_ms"]?.doubleValue
                        )
                    )
                }
                if record.recordType == DriftTransitionKind.engaged.rawValue, !sessions.isEmpty,
                   sessions[sessions.count - 1].engagedTime == nil {
                    sessions[sessions.count - 1].engagedTime = date
                }

            default:
                break
            }
        }

        return DriftTimeline(slopePoints: slopePoints, transitions: transitions, sessions: sessions)
    }

    private static func stage(of record: DiagnosticRecord, defaultEngagedStage: DriftStage) -> DriftStage {
        if let raw = record["model_stage"]?.stringValue {
            return DriftStage(rawValue: raw) ?? .unknown
        }
        if let stableEngaged = record["stable_engaged"]?.boolValue {
            return stableEngaged ? .stable : .warmup
        }
        // The first accepted fit's record doesn't carry model_stage or
        // stable_engaged -- it's always a warmup-stage fit by construction
        // (NetStation.py: the first fit that engages the model starts the
        // warmup window, and only a later fit can promote it to stable).
        if record.recordType == DriftTransitionKind.engaged.rawValue {
            return defaultEngagedStage
        }
        return .unknown
    }
}
