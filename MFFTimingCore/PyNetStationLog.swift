//
//  PyNetStationLog.swift
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
//  Decodes the JSON-lines diagnostic log egi_pynetstation writes via
//  NetStation.set_error_log()/_append_error_log(): one JSON object per line,
//  tagged by a "record" field (session_start, drift_model_engaged,
//  drift_model_status, drift_model_promoted, drift_model_stalled,
//  drift_model_recovered, drift_undersampled, event_send_failure,
//  display_timing, frame_interval_summary, ...). New record types are expected
//  as the Python package evolves, so records are kept as a flexible field bag
//  rather than one Codable case per type.
//

import Foundation

struct DiagnosticRecord: Identifiable, Sendable, Hashable {
    let index: Int
    let sourceFile: String
    /// The "record" field, e.g. "session_start", "drift_model_engaged".
    let recordType: String
    /// The "time" field: seconds since the Unix epoch, from Python's time.time()
    /// on the machine running the experiment script. Shares an epoch with the
    /// per-trial CSV's `local_time` column.
    let time: Double?
    let fields: [String: JSONValue]

    var id: Int { index }

    var date: Date? {
        time.map { Date(timeIntervalSince1970: $0) }
    }

    subscript(field: String) -> JSONValue? {
        fields[field]
    }
}

enum PyNetStationLogError: LocalizedError, Sendable {
    case unreadable(URL, String)
    case malformedLine(URL, Int, String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url, let message):
            return "Could not read \(url.lastPathComponent): \(message)"
        case .malformedLine(let url, let line, let message):
            return "\(url.lastPathComponent) line \(line) is not valid JSON: \(message)"
        }
    }
}

enum PyNetStationLog {
    /// Parses every line as an independent JSON object. Blank lines are
    /// skipped (the log is append-only and may end with a trailing newline).
    /// A line that fails to parse is reported by index, not fatal to the
    /// remaining lines -- a truncated last line from a session that ended
    /// mid-write shouldn't hide the rest of the log.
    static func load(from url: URL) throws -> (records: [DiagnosticRecord], errors: [PyNetStationLogError]) {
        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw PyNetStationLogError.unreadable(url, error.localizedDescription)
        }

        var records: [DiagnosticRecord] = []
        var errors: [PyNetStationLogError] = []
        let decoder = JSONDecoder()

        // Split on Unicode scalars, not `Character`: a CRLF line ending is a
        // single Swift `Character` (grapheme cluster), so splitting by the
        // `Character` "\n" would silently treat a whole CRLF file as one line.
        let lines = contents.unicodeScalars.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        for (offset, scalarLine) in lines.enumerated() {
            let line = String(String.UnicodeScalarView(scalarLine))
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let data = trimmed.data(using: .utf8) else {
                errors.append(.malformedLine(url, offset + 1, "Not valid UTF-8."))
                continue
            }

            do {
                let object = try decoder.decode([String: JSONValue].self, from: data)
                let recordType = object["record"]?.stringValue ?? "unknown"
                let time = object["time"]?.doubleValue
                records.append(
                    DiagnosticRecord(
                        index: records.count + 1,
                        sourceFile: url.lastPathComponent,
                        recordType: recordType,
                        time: time,
                        fields: object
                    )
                )
            } catch {
                errors.append(.malformedLine(url, offset + 1, error.localizedDescription))
            }
        }

        return (records, errors)
    }

    /// The diagnostic record whose `time` is closest to `epochSeconds`, within
    /// `tolerance` seconds. Used to explain a CSV row or MFF event by "what was
    /// the drift model doing right around then".
    static func nearest(to epochSeconds: Double, in records: [DiagnosticRecord], tolerance: Double = .infinity) -> DiagnosticRecord? {
        records
            .compactMap { record -> (DiagnosticRecord, Double)? in
                guard let time = record.time else { return nil }
                let delta = abs(time - epochSeconds)
                return delta <= tolerance ? (record, delta) : nil
            }
            .min { $0.1 < $1.1 }?
            .0
    }
}
