//
//  FormattingTests.swift
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

struct FormattingTests {
    @Test func elapsedFormatsUnderAnHourAsMinutesSeconds() {
        #expect(Formatting.elapsed(0) == "0:00")
        #expect(Formatting.elapsed(5) == "0:05")
        #expect(Formatting.elapsed(65) == "1:05")
        #expect(Formatting.elapsed(3599) == "59:59")
    }

    @Test func elapsedFormatsPastAnHourWithHours() {
        #expect(Formatting.elapsed(3600) == "1:00:00")
        #expect(Formatting.elapsed(3661) == "1:01:01")
    }

    @Test func elapsedClampsNegativeToZero() {
        #expect(Formatting.elapsed(-5) == "0:00")
    }

    @Test func signedDurationUsesMillisecondsUnderASecond() {
        #expect(Formatting.signedDuration(0.045) == "+45 ms")
        #expect(Formatting.signedDuration(-0.045) == "-45 ms")
    }

    @Test func signedDurationUsesSecondsAtOrAboveOne() {
        #expect(Formatting.signedDuration(1.5) == "+1.50 s")
        #expect(Formatting.signedDuration(-12.345) == "-12.35 s")
    }
}
