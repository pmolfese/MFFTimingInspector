//
//  MFFTrackClassifierTests.swift
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

struct MFFTrackClassifierTests {
    @Test func recognizesDINTracks() {
        #expect(MFFTrackClassifier.isDINLike(sourceFile: "Events_DIN.xml"))
        #expect(MFFTrackClassifier.isDINLike(sourceFile: "Events_DIN1.xml"))
        #expect(MFFTrackClassifier.isDINLike(sourceFile: "Events_DIN2.xml"))
    }

    @Test func recognizesMRPulseTrackRegardlessOfSpacingOrCase() {
        #expect(MFFTrackClassifier.isDINLike(sourceFile: "Events_MR_Pulse.xml"))
        #expect(MFFTrackClassifier.isDINLike(sourceFile: "Events_MR Pulse.xml"))
        #expect(MFFTrackClassifier.isDINLike(sourceFile: "events_mr_pulse.xml"))
    }

    @Test func doesNotFlagStimulusOrOtherTracks() {
        #expect(!MFFTrackClassifier.isDINLike(sourceFile: "Events_ECI.xml"))
        #expect(!MFFTrackClassifier.isDINLike(sourceFile: "Events_User Events.xml"))
        #expect(!MFFTrackClassifier.isDINLike(sourceFile: "Events_Markers.xml"))
    }
}
