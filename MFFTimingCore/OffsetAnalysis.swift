//
//  OffsetAnalysis.swift
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
//  Generalizes Tools/mffTimingTool's --code/--din/--pair offset calculation:
//  the CLI paired exactly one event code against exactly one DIN code. Here
//  either side can be any set of codes (e.g. both "EA++" and "EB++" against
//  DIN1, or "EA++" against DIN1+DIN2 pooled together), since which codes are
//  "the stimulus" and which are "the DIN" varies by paradigm and isn't
//  something the tool should hardcode.
//

import Foundation

struct OffsetPair: Identifiable, Sendable {
    let id: Int
    let primaryEvent: MFFEvent
    let referenceEvent: MFFEvent?

    /// referenceEvent.beginDate - primaryEvent.beginDate, in milliseconds.
    var deltaMilliseconds: Double? {
        guard let referenceEvent else { return nil }
        return referenceEvent.beginDate.timeIntervalSince(primaryEvent.beginDate) * 1000
    }
}

struct OffsetFrequencyRow: Identifiable, Sendable {
    var id: String { value }
    let value: String
    let count: Int
    let percent: Double
}

/// Which center a jitter table's "+/-N ms" buckets are measured from.
enum JitterCenter: String, CaseIterable, Identifiable, Sendable {
    case mean = "Average"
    case median = "Median"
    var id: String { rawValue }
}

/// One "+/-N ms" row: how many matched pairs landed within N ms (rounded) of
/// the chosen center, regardless of sign. The last bucket (`isOverflow`)
/// catches everything at or beyond `maxBucket`.
struct JitterBucket: Identifiable, Sendable {
    var id: Int { distanceMs }
    let distanceMs: Int
    let count: Int
    let percent: Double
    let isOverflow: Bool
}

struct HistogramBin: Identifiable, Sendable {
    var id: Int { binMs }
    let binMs: Int
    let count: Int
}

struct OffsetSummary: Sendable {
    let pairs: [OffsetPair]
    let matchedCount: Int
    let unmatchedCount: Int
    let minMs: Double?
    let maxMs: Double?
    let meanMs: Double?
    let medianMs: Double?
    let modeMs: String?
    let frequencyTable: [OffsetFrequencyRow]

    /// Every matched pair's offset in milliseconds, in pair order.
    var deltasMs: [Double] { pairs.compactMap(\.deltaMilliseconds) }

    /// Buckets matched offsets by rounded distance from `center` (mean or
    /// median), combining a pair 3ms early and a pair 3ms late into the same
    /// "+/-3" row -- the sign matters in the table above, not here.
    func jitterBuckets(center: JitterCenter, maxBucket: Int = 6) -> [JitterBucket] {
        let deltas = deltasMs
        guard !deltas.isEmpty else { return [] }
        let centerValue: Double
        switch center {
        case .mean: centerValue = meanMs ?? 0
        case .median: centerValue = medianMs ?? 0
        }

        var counts = [Int: Int]()
        for delta in deltas {
            let distance = Int((delta - centerValue).rounded())
            let bucket = min(abs(distance), maxBucket)
            counts[bucket, default: 0] += 1
        }

        let total = deltas.count
        return (0...maxBucket).map { bucket in
            let count = counts[bucket] ?? 0
            return JitterBucket(
                distanceMs: bucket,
                count: count,
                percent: Double(count) / Double(total) * 100,
                isOverflow: bucket == maxBucket
            )
        }
    }

    /// Raw offset values rounded to the nearest millisecond and binned for a
    /// histogram -- unlike `jitterBuckets`, this keeps sign and isn't
    /// centered, so it shows the actual shape of the distribution.
    func histogramBins() -> [HistogramBin] {
        let rounded = deltasMs.map { Int($0.rounded()) }
        guard !rounded.isEmpty else { return [] }
        let counts = Dictionary(grouping: rounded, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.key < $1.key }.map { HistogramBin(binMs: $0.key, count: $0.value) }
    }
}

enum OffsetAnalysis {
    /// For every event whose code is in `primaryCodes`, finds the paired
    /// event (per `pairMode`) among every event whose code is in
    /// `referenceCodes`, pooling all reference codes together as one
    /// candidate set -- so selecting DIN1+DIN2 as the reference matches each
    /// primary event to whichever of the two is nearer, not to each
    /// separately.
    static func computeOffsets(
        events: [MFFEvent],
        primaryCodes: Set<String>,
        referenceCodes: Set<String>,
        pairMode: PairMode
    ) -> OffsetSummary {
        let primaryEvents = events
            .filter { primaryCodes.contains($0.code) }
            .sorted { $0.beginDate < $1.beginDate }
        let referenceEvents = events
            .filter { referenceCodes.contains($0.code) }
            .sorted { $0.beginDate < $1.beginDate }

        // referenceEvents is already sorted by beginDate above, so this is an
        // O(log m) binary search per primary event -- see SortedMatch.swift.
        // A plain O(m) linear scan here, as MFFEventLoader.match does, is
        // fine for the CLI's single-pair use but is O(n*m) at UI scale
        // (thousands of events on each side), which measurably froze the app.
        var pairs: [OffsetPair] = []
        for (offset, event) in primaryEvents.enumerated() {
            let matched = SortedMatch.find(
                in: referenceEvents,
                nearestTo: event.beginDate.timeIntervalSinceReferenceDate,
                mode: pairMode,
                key: { $0.beginDate.timeIntervalSinceReferenceDate }
            )
            let pair = OffsetPair(id: offset, primaryEvent: event, referenceEvent: matched)
            pairs.append(pair)
        }

        return summarize(pairs)
    }

    /// Builds the derived statistics for an already-paired series. Project
    /// files use this to restore a plot from only (time, delta) numbers.
    static func summarize(_ pairs: [OffsetPair]) -> OffsetSummary {
        let deltasMs = pairs.compactMap(\.deltaMilliseconds)
        let rows = frequencyRows(deltasMs)
        return OffsetSummary(
            pairs: pairs,
            matchedCount: deltasMs.count,
            unmatchedCount: pairs.count - deltasMs.count,
            minMs: deltasMs.min(),
            maxMs: deltasMs.max(),
            meanMs: deltasMs.isEmpty ? nil : deltasMs.reduce(0, +) / Double(deltasMs.count),
            medianMs: deltasMs.isEmpty ? nil : median(deltasMs),
            modeMs: rows.first?.value,
            frequencyTable: rows
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2.0
        }
        return sorted[middle]
    }

    private static func frequencyRows(_ valuesMs: [Double]) -> [OffsetFrequencyRow] {
        guard !valuesMs.isEmpty else { return [] }
        let rounded = valuesMs.map { String(format: "%.3f", $0) }
        let counts = Dictionary(grouping: rounded, by: { $0 }).mapValues(\.count)
        let total = valuesMs.count

        return counts
            .sorted { left, right in
                if left.value == right.value {
                    return (Double(left.key) ?? 0) < (Double(right.key) ?? 0)
                }
                return left.value > right.value
            }
            .map { value, count in
                OffsetFrequencyRow(value: value, count: count, percent: Double(count) / Double(total) * 100)
            }
    }
}
