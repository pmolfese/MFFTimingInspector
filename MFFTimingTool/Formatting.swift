//
//  Formatting.swift
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

import Foundation

/// Whether a time-series chart labels its x-axis in absolute clock time or
/// time elapsed since the recording started.
enum TimeAxisMode: String, CaseIterable, Identifiable {
    case absolute = "Absolute time"
    case elapsed = "Since start"
    var id: String { rawValue }
}

enum Formatting {
    static let clockTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func seconds(_ value: Double?, digits: Int = 3) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f", value)
    }

    static func milliseconds(fromSeconds value: Double?, digits: Int = 1) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f ms", value * 1000)
    }

    static func milliseconds(fromMs value: Double?, digits: Int = 1) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f ms", value)
    }

    /// A signed duration, in seconds, scaled to whichever unit reads best:
    /// milliseconds under a second, seconds otherwise. Always includes the
    /// sign, since "before" vs. "after" is the point.
    static func signedDuration(_ seconds: Double) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let magnitude = abs(seconds)
        if magnitude < 1 {
            return String(format: "%@%.0f ms", sign, magnitude * 1000)
        }
        return String(format: "%@%.2f s", sign, magnitude)
    }

    /// A non-negative duration as a stopwatch reading: "M:SS", or "H:MM:SS"
    /// once it runs past an hour. Negative input (a date before the anchor
    /// it was measured from) is clamped to zero rather than shown signed --
    /// this is a "how far into the recording" label, not a delta.
    static func elapsed(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
