//
//  SortedMatchTests.swift
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
@testable import MFFTimingTool

struct SortedMatchTests {
    let values = [1.0, 3.0, 5.0, 5.0, 9.0, 20.0]

    @Test func lowerBoundFindsFirstIndexAtOrAboveTarget() {
        #expect(SortedMatch.lowerBoundIndex(values, target: 0.0, key: { $0 }) == 0)
        #expect(SortedMatch.lowerBoundIndex(values, target: 5.0, key: { $0 }) == 2) // first of the two 5.0s
        #expect(SortedMatch.lowerBoundIndex(values, target: 6.0, key: { $0 }) == 4)
        #expect(SortedMatch.lowerBoundIndex(values, target: 100.0, key: { $0 }) == values.count)
    }

    @Test func nearestPicksTheCloserNeighbor() {
        #expect(SortedMatch.find(in: values, nearestTo: 4.0, mode: .nearest, key: { $0 }) == 3.0)
        #expect(SortedMatch.find(in: values, nearestTo: 4.9, mode: .nearest, key: { $0 }) == 5.0)
        #expect(SortedMatch.find(in: values, nearestTo: 1000.0, mode: .nearest, key: { $0 }) == 20.0)
        #expect(SortedMatch.find(in: values, nearestTo: -1000.0, mode: .nearest, key: { $0 }) == 1.0)
    }

    @Test func nearestBreaksExactTiesTowardTheEarlierElement() {
        // 4.0 is exactly 1.0 away from both 3.0 and 5.0.
        #expect(SortedMatch.find(in: [3.0, 5.0], nearestTo: 4.0, mode: .nearest, key: { $0 }) == 3.0)
    }

    @Test func nextRequiresKeyAtOrAboveTarget() {
        #expect(SortedMatch.find(in: values, nearestTo: 4.0, mode: .next, key: { $0 }) == 5.0)
        #expect(SortedMatch.find(in: values, nearestTo: 5.0, mode: .next, key: { $0 }) == 5.0)
        #expect(SortedMatch.find(in: values, nearestTo: 21.0, mode: .next, key: { $0 }) == nil)
    }

    @Test func previousRequiresKeyAtOrBelowTarget() {
        #expect(SortedMatch.find(in: values, nearestTo: 4.0, mode: .previous, key: { $0 }) == 3.0)
        #expect(SortedMatch.find(in: values, nearestTo: 5.0, mode: .previous, key: { $0 }) == 5.0)
        #expect(SortedMatch.find(in: values, nearestTo: 0.0, mode: .previous, key: { $0 }) == nil)
    }

    @Test func emptyArrayFindsNothing() {
        let empty: [Double] = []
        for mode in [PairMode.nearest, .next, .previous] {
            #expect(SortedMatch.find(in: empty, nearestTo: 5.0, mode: mode, key: { $0 }) == nil)
        }
    }

    @Test func matchesLinearScanOverRandomizedData() {
        // Cross-check against the naive O(n) approach this replaced, across
        // enough targets and array sizes to catch an off-by-one at the edges.
        var generator = SystemRandomNumberGenerator()
        for size in [0, 1, 2, 5, 50] {
            let sorted = (0..<size).map { _ in Double.random(in: -100...100, using: &generator) }.sorted()
            for _ in 0..<20 {
                let target = Double.random(in: -120...120, using: &generator)
                for mode in [PairMode.nearest, .next, .previous] {
                    let fast = SortedMatch.find(in: sorted, nearestTo: target, mode: mode, key: { $0 })
                    let naive = linearFind(in: sorted, target: target, mode: mode)
                    #expect(fast == naive, "size=\(size) target=\(target) mode=\(mode)")
                }
            }
        }
    }

    private func linearFind(in sorted: [Double], target: Double, mode: PairMode) -> Double? {
        switch mode {
        case .nearest:
            return sorted.min { abs($0 - target) < abs($1 - target) }
        case .next:
            return sorted.filter { $0 >= target }.min()
        case .previous:
            return sorted.filter { $0 <= target }.max()
        }
    }
}
