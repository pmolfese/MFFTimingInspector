//
//  InspectorView.swift
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

import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let match = appState.selectedMatch {
                    mffSection(match.mffEvent)
                    if let trial = match.trial {
                        trialSection(trial, deltaSeconds: match.deltaSeconds)
                    } else {
                        noMatchSection
                    }
                    if let diagnostic = appState.nearestDiagnosticForSelection {
                        diagnosticSection(diagnostic)
                    }
                } else {
                    Text("Select an event to inspect it.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private func mffSection(_ event: MFFEvent) -> some View {
        InspectorSection(title: "MFF event #\(event.index)") {
            field("code", event.code)
            field("MFF time", Formatting.clockTime.string(from: event.beginDate))
            if let relative = event.relativeBeginTimeSeconds {
                field("relative", Formatting.seconds(relative) + " s")
            }
            if let label = event.label { field("label", label) }
            if let device = event.sourceDevice { field("source", device) }
            ForEach(event.keys.keys.sorted(), id: \.self) { key in
                field(key, event.keys[key] ?? "")
            }
        }
    }

    @ViewBuilder
    private func trialSection(_ trial: TrialRecord, deltaSeconds: Double?) -> some View {
        InspectorSection(title: "pynetstation trial #\(trial.trialIndex.map(String.init) ?? "?")") {
            if let deltaSeconds {
                field("Δ to MFF", Formatting.milliseconds(fromSeconds: deltaSeconds))
            }
            field("event code", trial.eventCode ?? "—")
            field("intended trigger", trial.intendedTrigger ?? "—")
            field("psychopy_time", Formatting.seconds(trial.psychopyTime) + " s")
            field("package_time", Formatting.seconds(trial.packageTime) + " s")
            field("local_time", trial.localTime.map { String(format: "%.6f", $0) } ?? "—")
            field("send_result", trial.sendResult ?? "—")
            if let sendError = trial.sendError, !sendError.isEmpty {
                field("send_error", sendError)
            }
            if let stage = trial.driftModelStage {
                field("drift stage", stage)
            }
            if let driftMs = trial.driftCorrectionMs {
                field("drift correction", Formatting.seconds(driftMs, digits: 3) + " ms")
            }
        }
    }

    private var noMatchSection: some View {
        InspectorSection(title: "pynetstation trial") {
            Text("No CSV row matched this event within tolerance.")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func diagnosticSection(_ record: DiagnosticRecord) -> some View {
        InspectorSection(title: "nearest diagnostic: \(record.recordType)") {
            if let date = record.date {
                field("time", Formatting.clockTime.string(from: date))
            }
            ForEach(record.fields.keys.sorted().filter { $0 != "record" && $0 != "time" }, id: \.self) { key in
                if let value = record.fields[key] {
                    field(key, value.displayString)
                }
            }
        }
    }

    @ViewBuilder
    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(.bottom, 4)
        Divider()
    }
}
