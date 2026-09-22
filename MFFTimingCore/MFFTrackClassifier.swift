//
//  MFFTrackClassifier.swift
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
//  Recognizes which Events*.xml track an event came from, so the offset
//  analysis UI can offer a "DIN-like" quick-select instead of requiring
//  every reference code to be picked by hand. DIN pulses and external sync
//  pulses (e.g. an MRI scanner's TR trigger, recorded in
//  "Events_MR_Pulse.xml") behave the same way here: they're external timing
//  references to compare a stimulus code against, whatever NetStation named
//  their track.
//

import Foundation

enum MFFTrackClassifier {
    /// True for a source file recognizable as carrying external timing-reference
    /// pulses rather than stimulus/behavioral codes: any "Events_DIN*.xml"
    /// track, and "Events_MR_Pulse.xml" (MRI scanner TR triggers in
    /// simultaneous EEG-fMRI recordings).
    static func isDINLike(sourceFile: String) -> Bool {
        let normalized = sourceFile.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalized.contains("din") || normalized.contains("mrpulse")
    }
}
