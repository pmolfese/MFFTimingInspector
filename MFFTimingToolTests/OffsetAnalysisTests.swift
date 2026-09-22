//
//  OffsetAnalysisTests.swift
//  MFFTimingToolTests
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

import Testing
import Foundation
@testable import MFFTimingTool

struct OffsetAnalysisTests {
    func stagedMFF() throws -> URL {
        let eventsFile = Fixtures.url("Events_din.xml")
        let mffDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathExtension("mff")
        try FileManager.default.createDirectory(at: mffDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: eventsFile, to: mffDirectory.appendingPathComponent("Events_din.xml"))
        return mffDirectory
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func singleCodeAgainstSingleDIN() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)

        let summary = OffsetAnalysis.computeOffsets(
            events: events,
            primaryCodes: ["EA++"],
            referenceCodes: ["DIN1"],
            pairMode: .nearest
        )

        #expect(summary.pairs.count == 3)
        #expect(summary.matchedCount == 3)
        #expect(summary.unmatchedCount == 0)
        // Each EA++ is ~20ms before its DIN1.
        for pair in summary.pairs {
            #expect(pair.referenceEvent?.code == "DIN1")
            #expect(abs((pair.deltaMilliseconds ?? 0) - 20) < 1.5)
        }
        #expect(abs((summary.meanMs ?? 0) - 20) < 1.5)
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func pooledReferenceCodesMatchWhicheverIsNearer() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)

        // EA++ and EB++ against BOTH DIN1 and DIN2 pooled: each primary event
        // should match its own DIN (EA++ -> DIN1, EB++ -> DIN2) because that's
        // nearer, not because of any code-to-code rule.
        let summary = OffsetAnalysis.computeOffsets(
            events: events,
            primaryCodes: ["EA++", "EB++"],
            referenceCodes: ["DIN1", "DIN2"],
            pairMode: .nearest
        )

        // Fixture has 3 EA++ events and 2 EB++ events.
        #expect(summary.pairs.count == 5)
        #expect(summary.matchedCount == 5)

        let eaPairs = summary.pairs.filter { $0.primaryEvent.code == "EA++" }
        let ebPairs = summary.pairs.filter { $0.primaryEvent.code == "EB++" }
        #expect(eaPairs.count == 3)
        #expect(ebPairs.count == 2)
        #expect(eaPairs.allSatisfy { $0.referenceEvent?.code == "DIN1" })
        #expect(ebPairs.allSatisfy { $0.referenceEvent?.code == "DIN2" })
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func unmatchedPrimaryWhenNoReferenceEventsExist() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)

        let summary = OffsetAnalysis.computeOffsets(
            events: events,
            primaryCodes: ["EA++"],
            referenceCodes: ["DIN9"], // not present
            pairMode: .nearest
        )

        #expect(summary.pairs.count == 3)
        #expect(summary.matchedCount == 0)
        #expect(summary.unmatchedCount == 3)
        #expect(summary.meanMs == nil)
        #expect(summary.pairs.allSatisfy { $0.referenceEvent == nil })
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func nextPairModeRequiresReferenceAfterPrimary() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)

        let summary = OffsetAnalysis.computeOffsets(
            events: events,
            primaryCodes: ["EA++"],
            referenceCodes: ["DIN1"],
            pairMode: .next
        )

        for pair in summary.pairs {
            #expect((pair.deltaMilliseconds ?? -1) >= 0)
        }
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func minMaxBracketTheDeltas() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)

        let summary = OffsetAnalysis.computeOffsets(
            events: events,
            primaryCodes: ["EA++"],
            referenceCodes: ["DIN1"],
            pairMode: .nearest
        )

        // Deltas are ~19, ~20.999, ~19 -- min/max should bracket every delta.
        let deltas = summary.deltasMs
        #expect(summary.minMs == deltas.min())
        #expect(summary.maxMs == deltas.max())
        #expect((summary.minMs ?? .infinity) <= (summary.medianMs ?? 0))
        #expect((summary.maxMs ?? -.infinity) >= (summary.medianMs ?? 0))
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func jitterBucketsSumToMatchedCountAndAreCenterSensitive() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)

        let summary = OffsetAnalysis.computeOffsets(
            events: events,
            primaryCodes: ["EA++"],
            referenceCodes: ["DIN1"],
            pairMode: .nearest
        )

        for center in JitterCenter.allCases {
            let buckets = summary.jitterBuckets(center: center)
            let total = buckets.reduce(0) { $0 + $1.count }
            #expect(total == summary.matchedCount)
            // Every offset is within 6ms of either center for this fixture,
            // so nothing should land in the overflow bucket.
            #expect(buckets.last?.count == 0)
        }
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func histogramBinsPreserveTotalCountAndSign() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)

        let summary = OffsetAnalysis.computeOffsets(
            events: events,
            primaryCodes: ["EA++"],
            referenceCodes: ["DIN1"],
            pairMode: .nearest
        )

        let bins = summary.histogramBins()
        #expect(bins.reduce(0) { $0 + $1.count } == summary.matchedCount)
        // All EA++ -> DIN1 deltas are positive (DIN follows the stimulus).
        #expect(bins.allSatisfy { $0.binMs > 0 })
        // Bins are sorted ascending by offset.
        for (a, b) in zip(bins, bins.dropFirst()) {
            #expect(a.binMs < b.binMs)
        }
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func emptySelectionProducesNoDistributionData() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)

        let summary = OffsetAnalysis.computeOffsets(
            events: events,
            primaryCodes: ["EA++"],
            referenceCodes: ["DIN9"], // not present
            pairMode: .nearest
        )

        #expect(summary.minMs == nil)
        #expect(summary.maxMs == nil)
        #expect(summary.jitterBuckets(center: .median).isEmpty)
        #expect(summary.histogramBins().isEmpty)
    }

    @Test(.enabled(if: Fixtures.exists("Events_din.xml"))) func frequencyTableSumsToTotalMatched() throws {
        let mff = try stagedMFF()
        defer { try? FileManager.default.removeItem(at: mff) }
        let events = try MFFEventLoader.loadEvents(from: mff)

        let summary = OffsetAnalysis.computeOffsets(
            events: events,
            primaryCodes: ["EA++", "EB++"],
            referenceCodes: ["DIN1", "DIN2"],
            pairMode: .nearest
        )

        let totalInTable = summary.frequencyTable.reduce(0) { $0 + $1.count }
        #expect(totalInTable == summary.matchedCount)
        #expect(summary.modeMs == summary.frequencyTable.first?.value)
    }
}
