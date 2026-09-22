//
//  TrialRecord.swift
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
//  Typed view over the per-trial "egi_timing.csv" that experiment scripts
//  (e.g. example5_psychopy_photocell_drift.py) write alongside the JSONL
//  diagnostic log. Columns beyond the ones modeled here are kept in `rawFields`
//  so a driver script's custom columns still show up in the inspector.
//

import Foundation

struct TrialRecord: Identifiable, Sendable, Hashable {
    let index: Int
    let sourceFile: String
    let rawFields: [String: String]

    var id: Int { index }

    /// e.g. "egi_event", "recording_started", "recording_ended", or a
    /// driver-defined milestone like "rest_eyes_open_end".
    var recordType: String { rawFields["record_type"] ?? "" }
    var eventCode: String? { nonEmpty("event_code") }
    var eventType: String? { nonEmpty("event_type") }
    var eventLabel: String? { nonEmpty("event_label") }
    var intendedTrigger: String? { nonEmpty("intended_trigger") }
    var blockNum: Int? { int("block_num") }
    var trialIndex: Int? { int("trial_index") }
    var stimType: String? { nonEmpty("stim_type") }
    var toneFreq: Double? { double("tone_freq") }

    /// PsychoPy's MonotonicClock, seconds since that clock's own zero.
    var psychopyTime: Double? { double("psychopy_time") }
    /// egi_pynetstation's ns.getTime(), NTP/drift-corrected, seconds since connect().
    var packageTime: Double? { double("package_time") }
    var packageMinusPsychopyMs: Double? { double("package_minus_psychopy_ms") }
    /// Python time.time() epoch -- shares a clock with the JSONL log's `time` field.
    var localTime: Double? { double("local_time") }
    var captureTime: Double? { double("capture_time") }
    var sendCallSpanMs: Double? { double("send_call_span_ms") }
    var pendingEvents: Int? { int("pending_events") }
    var sendResult: String? { nonEmpty("send_result") }
    var sendError: String? { nonEmpty("send_error") }

    var toneScheduledTime: Double? { double("tone_scheduled_time") }
    var toneFlipTime: Double? { double("tone_flip_time") }
    var toneToEventCallMs: Double? { double("tone_to_event_call_ms") }

    var measuredFps: Double? { double("measured_fps") }
    var framePeriodMs: Double? { double("frame_period_ms") }
    var driftCorrectionMs: Double? { double("drift_correction_ms") }
    var driftSlopeMsPerHour: Double? { double("drift_slope_ms_per_hour") }
    var driftSamples: Int? { int("drift_samples") }
    var driftValidSamples: Int? { int("drift_valid_samples") }
    var driftRejectedSamples: Int? { int("drift_rejected_samples") }
    var driftModelStage: String? { nonEmpty("drift_model_stage") }
    var driftModelAgeSeconds: Double? { double("drift_model_age_s") }
    var clockStateError: String? { nonEmpty("clock_state_error") }

    /// True when send_error is non-empty or send_result isn't "sent".
    var isSendFailure: Bool {
        if let sendError, !sendError.isEmpty { return true }
        if let sendResult, sendResult != "sent" { return true }
        return false
    }

    private func nonEmpty(_ key: String) -> String? {
        guard let value = rawFields[key], !value.isEmpty else { return nil }
        return value
    }

    private func double(_ key: String) -> Double? {
        nonEmpty(key).flatMap(Double.init)
    }

    private func int(_ key: String) -> Int? {
        nonEmpty(key).flatMap(Int.init)
    }
}

enum TrialCSV {
    static func load(from url: URL) throws -> [TrialRecord] {
        let table = try CSVTable.parse(contentsOf: url)
        return table.rows.enumerated().map { offset, row in
            TrialRecord(index: offset + 1, sourceFile: url.lastPathComponent, rawFields: row)
        }
    }
}
