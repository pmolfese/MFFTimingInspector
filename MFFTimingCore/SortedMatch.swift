//
//  SortedMatch.swift
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
//  Nearest/next/previous lookup in a key-ascending-sorted array, via binary
//  search: O(log n) per lookup instead of the O(n) linear scan a naive
//  `.min(by:)` does. At a few thousand same-code events matched against a
//  few thousand candidates, the linear version is O(n^2) -- measured at
//  ~2.2 SECONDS per call on realistic data in a debug build, which is what
//  actually froze the UI on every click. Both Correlator.matchMFFEvents and
//  OffsetAnalysis.computeOffsets pre-sort their candidates once and use this.
//

import Foundation

enum SortedMatch {
    /// The first index in `elements` (sorted ascending by `key`) whose key is
    /// >= `target`, or `elements.count` if every key is smaller.
    static func lowerBoundIndex<T>(_ elements: [T], target: Double, key: (T) -> Double) -> Int {
        var low = 0
        var high = elements.count
        while low < high {
            let mid = (low + high) / 2
            if key(elements[mid]) < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// `elements` must already be sorted ascending by `key`. Ties (equal
    /// distance in `.nearest`, or an exact `target` match in `.next`/
    /// `.previous`) resolve to the earlier-sorted element.
    static func find<T>(in elements: [T], nearestTo target: Double, mode: PairMode, key: (T) -> Double) -> T? {
        guard !elements.isEmpty else { return nil }
        let idx = lowerBoundIndex(elements, target: target, key: key)

        switch mode {
        case .next:
            return idx < elements.count ? elements[idx] : nil

        case .previous:
            if idx < elements.count, key(elements[idx]) == target {
                return elements[idx]
            }
            return idx > 0 ? elements[idx - 1] : nil

        case .nearest:
            let after: T? = idx < elements.count ? elements[idx] : nil
            let before: T? = idx > 0 ? elements[idx - 1] : nil
            switch (before, after) {
            case (nil, nil): return nil
            case (let b?, nil): return b
            case (nil, let a?): return a
            case (let b?, let a?):
                let beforeDistance = abs(key(b) - target)
                let afterDistance = abs(key(a) - target)
                return afterDistance < beforeDistance ? a : b
            }
        }
    }
}
