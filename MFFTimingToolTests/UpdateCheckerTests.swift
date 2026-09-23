//
//  UpdateCheckerTests.swift
//  MFFTimingToolTests
//

import Testing
@testable import MFFTimingTool

@MainActor
struct UpdateCheckerTests {
    @Test func comparesNumericReleaseVersions() {
        #expect(UpdateChecker.isVersion("v0.2.0", newerThan: "0.1.0") == true)
        #expect(UpdateChecker.isVersion("1.10.0", newerThan: "1.9.9") == true)
        #expect(UpdateChecker.isVersion("v1.2", newerThan: "1.2.0") == false)
        #expect(UpdateChecker.isVersion("0.0.9", newerThan: "0.1.0") == false)
    }

    @Test func ignoresPrereleaseSuffixForNumericComparison() {
        #expect(UpdateChecker.isVersion("v2.0.0-beta.1", newerThan: "1.9.0") == true)
    }

    @Test func rejectsMalformedReleaseTags() {
        #expect(UpdateChecker.isVersion("latest", newerThan: "1.0.0") == nil)
        #expect(UpdateChecker.isVersion("v1.two.0", newerThan: "1.0.0") == nil)
    }
}
